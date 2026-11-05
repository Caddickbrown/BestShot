//! Reading and editing XMP packets: `xmp:Rating`, `xmp:Label` and `dc:subject`
//! (plus Bridge's `photoshop:LabelColor`).
//!
//! Edits are splices into the original text, never a re-serialisation, so
//! everything else in the packet (Camera Raw settings, history, padding,
//! comments) stays byte-for-byte as it was. Only properties directly on a
//! top-level `rdf:Description` count: `crs:Look` and `xmpMM:Pantry` hold nested
//! descriptions that can carry their own `xmp:Rating`.

use quick_xml::escape::unescape;
use quick_xml::events::{BytesStart, Event};
use quick_xml::Reader;
use serde::{Deserialize, Serialize};

const NS_RDF: &str = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";
const NS_XMP: &str = "http://ns.adobe.com/xap/1.0/";
const NS_DC: &str = "http://purl.org/dc/elements/1.1/";
const NS_PHOTOSHOP: &str = "http://ns.adobe.com/photoshop/1.0/";

/// What BestShot reads from a packet, exactly as stored: label text is mapped
/// to a colour later, so changing the mapping never means re-reading files.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Fields {
    /// 1-5 stars, or -1 for Bridge's "Reject" rating. `None` is unrated.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rating: Option<i8>,
    /// `xmp:Label`: free text, user-configurable in Bridge.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    /// `photoshop:LabelColor`, which Bridge may leave alongside it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label_color: Option<String>,
    /// `dc:subject`, in file order.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub keywords: Vec<String>,
}

impl Fields {
    pub fn is_empty(&self) -> bool {
        *self == Fields::default()
    }
}

/// An edit: `None` leaves a field alone, `Some(None)` removes it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Change {
    pub rating: Option<Option<i8>>,
    pub label: Option<Option<String>>,
    pub label_color: Option<Option<String>>,
    pub keywords: Option<Vec<String>>,
}

impl Change {
    /// The change that writes `fields` in full.
    pub fn all(fields: &Fields) -> Self {
        Self {
            rating: Some(fields.rating),
            label: Some(fields.label.clone()),
            label_color: Some(fields.label_color.clone()),
            keywords: Some(fields.keywords.clone()),
        }
    }

    pub fn applied_to(&self, fields: &Fields) -> Fields {
        Fields {
            rating: self.rating.unwrap_or(fields.rating),
            label: self.label.clone().unwrap_or_else(|| fields.label.clone()),
            label_color: self.label_color.clone().unwrap_or_else(|| fields.label_color.clone()),
            keywords: self.keywords.clone().unwrap_or_else(|| fields.keywords.clone()),
        }
    }
}

/// Parses a packet from raw bytes. XMP sidecars are UTF-8 in practice; anything
/// else is reported rather than guessed at.
pub fn parse_bytes(bytes: &[u8]) -> Result<Fields, String> {
    parse(std::str::from_utf8(bytes).map_err(|_| "not UTF-8 text".to_string())?)
}

pub fn parse(text: &str) -> Result<Fields, String> {
    let doc = Doc::scan(strip_bom(text))?;
    Ok(doc.fields())
}

/// Applies `change`, returning the new packet. The result is re-parsed and
/// checked before it's handed back, so a bad edit can't reach the disk.
pub fn apply(text: &str, change: &Change) -> Result<String, String> {
    let body = strip_bom(text);
    let bom = &text[..text.len() - body.len()];
    let before = Doc::scan(body)?.fields();
    let want = change.applied_to(&before);

    let mut out = body.to_string();
    if want.rating != before.rating {
        out = set_simple(&out, NS_XMP, "Rating", "xmp", want.rating.map(|r| r.to_string()).as_deref())?;
    }
    if want.label != before.label {
        out = set_simple(&out, NS_XMP, "Label", "xmp", want.label.as_deref())?;
    }
    if want.label_color != before.label_color {
        out = set_simple(&out, NS_PHOTOSHOP, "LabelColor", "photoshop", want.label_color.as_deref())?;
    }
    if want.keywords != before.keywords {
        out = set_keywords(&out, &want.keywords)?;
    }

    let after = Doc::scan(&out).map_err(|e| format!("edit produced invalid XMP: {e}"))?.fields();
    if after != want {
        return Err("edit didn't read back as written".into());
    }
    Ok(format!("{bom}{out}"))
}

/// A new packet holding `fields`, for files with no sidecar yet.
pub fn new_packet(fields: &Fields) -> Result<String, String> {
    let empty = format!(
        "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n\
         <x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"BestShot\">\n \
         <rdf:RDF xmlns:rdf=\"{NS_RDF}\">\n  \
         <rdf:Description rdf:about=\"\"\n    xmlns:xmp=\"{NS_XMP}\"\n    xmlns:dc=\"{NS_DC}\">\n  \
         </rdf:Description>\n \
         </rdf:RDF>\n\
         </x:xmpmeta>\n\
         <?xpacket end=\"w\"?>\n"
    );
    apply(&empty, &Change::all(fields))
}

fn strip_bom(text: &str) -> &str {
    text.strip_prefix('\u{FEFF}').unwrap_or(text)
}

fn escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            // Illegal in XML 1.0, so they can't be written at all.
            c if (c as u32) < 0x20 && !matches!(c, '\t' | '\n' | '\r') => {}
            c => out.push(c),
        }
    }
    out
}

/// One property of a top-level description.
#[derive(Debug)]
struct Prop {
    ns: String,
    local: String,
    /// The whole property, including the whitespace before it.
    span: (usize, usize),
    /// Attribute value or element content, still escaped.
    inner: (usize, usize),
    is_attr: bool,
    /// Text of each `rdf:li`, for array values.
    items: Vec<String>,
    value: String,
}

/// A top-level `rdf:Description`.
#[derive(Debug)]
struct Desc {
    /// Where a new attribute goes, and the whitespace to put before it.
    attr_at: usize,
    attr_sep: String,
    /// Start of the closing tag; `None` if self-closing.
    close: Option<usize>,
    about: String,
    /// In-scope namespaces at the description (prefix, URI).
    scope: Vec<(String, String)>,
}

#[derive(Debug)]
struct Doc {
    props: Vec<Prop>,
    descs: Vec<Desc>,
    /// Prefix the document uses for RDF, with its colon (often `rdf:`).
    rdf: String,
    /// Start of `</rdf:RDF>`.
    rdf_close: Option<usize>,
}

struct Attr {
    name: String,
    ws_start: usize,
    name_start: usize,
    value: (usize, usize),
}

/// Offsets of each attribute in a start tag that quick-xml has already
/// validated. Offsets are relative to the start of `tag`.
fn attr_spans(tag: &str) -> Result<(usize, Vec<Attr>), String> {
    let b = tag.as_bytes();
    let bad = || format!("malformed tag {}", tag.chars().take(60).collect::<String>());
    let mut i = 1;
    while i < b.len() && !b[i].is_ascii_whitespace() && b[i] != b'>' && b[i] != b'/' {
        i += 1;
    }
    let name_end = i;
    let mut attrs = Vec::new();
    loop {
        let ws_start = i;
        while i < b.len() && b[i].is_ascii_whitespace() {
            i += 1;
        }
        if i >= b.len() || b[i] == b'>' || b[i] == b'/' {
            return Ok((name_end, attrs));
        }
        let start = i;
        while i < b.len() && b[i] != b'=' && !b[i].is_ascii_whitespace() {
            i += 1;
        }
        let name = tag[start..i].to_string();
        while i < b.len() && (b[i].is_ascii_whitespace() || b[i] == b'=') {
            i += 1;
        }
        let quote = *b.get(i).ok_or_else(bad)?;
        if quote != b'"' && quote != b'\'' {
            return Err(bad());
        }
        i += 1;
        let value_start = i;
        while i < b.len() && b[i] != quote {
            i += 1;
        }
        if i >= b.len() {
            return Err(bad());
        }
        attrs.push(Attr { name, ws_start, name_start: start, value: (value_start, i) });
        i += 1;
    }
}

fn split_name(name: &str) -> (&str, &str) {
    name.split_once(':').unwrap_or(("", name))
}

fn resolve<'a>(scope: &'a [(String, String)], prefix: &str) -> Option<&'a str> {
    scope.iter().rev().find(|(p, _)| p == prefix).map(|(_, uri)| uri.as_str())
}

/// Decodes element text, allowing for CDATA sections.
fn decode(raw: &str) -> Result<String, String> {
    let mut out = String::new();
    let mut rest = raw;
    while let Some(i) = rest.find("<![CDATA[") {
        out.push_str(&unescape(&rest[..i]).map_err(|e| e.to_string())?);
        let body = &rest[i + 9..];
        let end = body.find("]]>").ok_or("unterminated CDATA")?;
        out.push_str(&body[..end]);
        rest = &body[end + 3..];
    }
    out.push_str(&unescape(rest).map_err(|e| e.to_string())?);
    Ok(out)
}

/// An open element.
struct Frame {
    scope_len: usize,
    is_rdf_root: bool,
    /// Index into `Doc::descs`, for a top-level description.
    desc: Option<usize>,
    /// For a property element: where it started and where its content starts.
    prop: Option<OpenProp>,
    /// For an `rdf:li` inside a property.
    li_start: Option<usize>,
}

struct OpenProp {
    ns: String,
    local: String,
    start: usize,
    inner_start: usize,
    items: Vec<String>,
}

impl Doc {
    fn scan(text: &str) -> Result<Doc, String> {
        let mut reader = Reader::from_str(text);
        let mut doc = Doc { props: Vec::new(), descs: Vec::new(), rdf: String::new(), rdf_close: None };
        let mut scope: Vec<(String, String)> = vec![("xml".into(), "http://www.w3.org/XML/1998/namespace".into())];
        let mut stack: Vec<Frame> = Vec::new();
        let mut rdf_depth = None;
        let mut seen_root = false;

        loop {
            let start = reader.buffer_position() as usize;
            let event = reader.read_event().map_err(|e| format!("not valid XML: {e}"))?;
            let end = reader.buffer_position() as usize;
            match event {
                Event::Eof => break,
                Event::Empty(e) => {
                    seen_root = true;
                    let frame = doc.open(&e, text, start, end, &mut scope, &stack, &mut rdf_depth)?;
                    doc.close(frame, text, start, end, &mut scope, &mut stack, true)?;
                }
                Event::Start(e) => {
                    seen_root = true;
                    let frame = doc.open(&e, text, start, end, &mut scope, &stack, &mut rdf_depth)?;
                    stack.push(frame);
                }
                Event::End(_) => {
                    let frame = stack.pop().ok_or("unexpected closing tag")?;
                    doc.close(frame, text, start, end, &mut scope, &mut stack, false)?;
                }
                Event::Text(_) if stack.is_empty() && !text[start..end].trim().is_empty() => {
                    return Err("text outside the root element".into());
                }
                _ => {}
            }
        }
        if !stack.is_empty() {
            return Err("truncated: elements left open".into());
        }
        if !seen_root || rdf_depth.is_none() {
            return Err("no rdf:RDF element".into());
        }
        Ok(doc)
    }

    #[allow(clippy::too_many_arguments)]
    fn open(
        &mut self,
        e: &BytesStart,
        text: &str,
        start: usize,
        end: usize,
        scope: &mut Vec<(String, String)>,
        stack: &[Frame],
        rdf_depth: &mut Option<usize>,
    ) -> Result<Frame, String> {
        for attr in e.attributes() {
            attr.map_err(|err| format!("bad attribute: {err}"))?;
        }
        let tag = &text[start..end];
        let (name_end, attrs) = attr_spans(tag)?;
        let name = &tag[1..name_end];
        let scope_len = scope.len();
        for a in &attrs {
            let uri = decode(&tag[a.value.0..a.value.1])?;
            if a.name == "xmlns" {
                scope.push((String::new(), uri));
            } else if let Some(prefix) = a.name.strip_prefix("xmlns:") {
                scope.push((prefix.to_string(), uri));
            }
        }
        let (prefix, local) = split_name(name);
        let ns = resolve(scope, prefix).unwrap_or("").to_string();
        let depth = stack.len();
        let mut frame = Frame { scope_len, is_rdf_root: false, desc: None, prop: None, li_start: None };

        match *rdf_depth {
            None if ns == NS_RDF && local == "RDF" => {
                *rdf_depth = Some(depth);
                self.rdf = if prefix.is_empty() { String::new() } else { format!("{prefix}:") };
                frame.is_rdf_root = true;
            }
            Some(d) if depth == d + 1 && ns == NS_RDF && local == "Description" => {
                frame.desc = Some(self.descs.len());
                self.add_desc(tag, name_end, &attrs, start, scope)?;
            }
            Some(d) if depth == d + 2 && stack.last().is_some_and(|f| f.desc.is_some()) => {
                frame.prop = Some(OpenProp { ns, local: local.to_string(), start, inner_start: end, items: Vec::new() });
            }
            Some(_) if ns == NS_RDF && local == "li" && Self::in_array(stack) => {
                frame.li_start = Some(end);
            }
            _ => {}
        }
        Ok(frame)
    }

    /// True when the parent is an array directly inside a property.
    fn in_array(stack: &[Frame]) -> bool {
        stack.len() >= 2 && stack[stack.len() - 2].prop.is_some()
    }

    fn add_desc(&mut self, tag: &str, name_end: usize, attrs: &[Attr], start: usize, scope: &[(String, String)]) -> Result<(), String> {
        let mut about = String::new();
        for a in attrs {
            let (prefix, local) = split_name(&a.name);
            let value = (start + a.value.0, start + a.value.1);
            if prefix == "xmlns" || a.name == "xmlns" {
                continue;
            }
            let ns = if prefix.is_empty() { "" } else { resolve(scope, prefix).unwrap_or("") };
            if local == "about" && (ns == NS_RDF || prefix.is_empty()) {
                about = tag[a.value.0..a.value.1].to_string();
            } else {
                self.props.push(Prop {
                    ns: ns.to_string(),
                    local: local.to_string(),
                    span: (start + a.ws_start, value.1 + 1),
                    inner: value,
                    is_attr: true,
                    items: Vec::new(),
                    value: decode(&tag[a.value.0..a.value.1])?,
                });
            }
        }
        let (attr_at, attr_sep) = match attrs.last() {
            Some(last) => (start + last.value.1 + 1, tag[last.ws_start..last.name_start].to_string()),
            None => (start + name_end, " ".to_string()),
        };
        self.descs.push(Desc { attr_at, attr_sep, close: None, about, scope: scope.to_vec() });
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn close(
        &mut self,
        frame: Frame,
        text: &str,
        start: usize,
        end: usize,
        scope: &mut Vec<(String, String)>,
        stack: &mut [Frame],
        self_closed: bool,
    ) -> Result<(), String> {
        scope.truncate(frame.scope_len);
        if frame.is_rdf_root && !self_closed {
            self.rdf_close = Some(start);
        }
        if let Some(i) = frame.desc {
            if !self_closed {
                self.descs[i].close = Some(start);
            }
        }
        if let Some(li_start) = frame.li_start {
            let value = if self_closed { String::new() } else { decode(&text[li_start..start])? };
            if let Some(prop) = stack.iter_mut().rev().nth(1).and_then(|f| f.prop.as_mut()) {
                prop.items.push(value);
            }
        }
        if let Some(p) = frame.prop {
            let inner = if self_closed { (end, end) } else { (p.inner_start, start) };
            let raw = &text[inner.0..inner.1];
            // Array values have been collected; only plain text decodes as text.
            let value = if raw.replace("<![CDATA[", "").contains('<') { String::new() } else { decode(raw)? };
            let ws = text[..p.start].trim_end_matches([' ', '\t', '\r', '\n']).len();
            self.props.push(Prop {
                ns: p.ns,
                local: p.local,
                span: (ws, end),
                inner,
                is_attr: false,
                items: p.items,
                value,
            });
        }
        Ok(())
    }

    fn find(&self, ns: &str, local: &str) -> impl Iterator<Item = &Prop> {
        let (ns, local) = (ns.to_string(), local.to_string());
        self.props.iter().filter(move |p| p.ns == ns && p.local == local)
    }

    fn simple(&self, ns: &str, local: &str) -> Option<String> {
        self.find(ns, local)
            .map(|p| p.items.first().cloned().unwrap_or_else(|| p.value.clone()))
            .map(|v| v.trim().to_string())
            .find(|v| !v.is_empty())
    }

    fn fields(&self) -> Fields {
        let keywords: Vec<String> = self
            .find(NS_DC, "subject")
            .flat_map(|p| if p.is_attr || p.items.is_empty() { vec![p.value.clone()] } else { p.items.clone() })
            .map(|k| k.trim().to_string())
            .filter(|k| !k.is_empty())
            .collect();
        Fields {
            rating: self.simple(NS_XMP, "Rating").and_then(|r| parse_rating(&r)),
            label: self.simple(NS_XMP, "Label"),
            label_color: self.simple(NS_PHOTOSHOP, "LabelColor"),
            keywords,
        }
    }

    fn rdf_tag(&self, local: &str) -> String {
        format!("{}{local}", self.rdf)
    }
}

/// `xmp:Rating` is a real number: 1-5 stars, 0 for none, -1 for "Reject".
/// An empty or out-of-range value counts as unrated.
fn parse_rating(raw: &str) -> Option<i8> {
    let n = raw.trim().parse::<f64>().ok()?;
    if n == -1.0 {
        Some(-1)
    } else if (0.5..=5.0).contains(&n) {
        Some(n.round() as i8)
    } else {
        None
    }
}

/// Applies non-overlapping `(start, end, replacement)` edits.
fn splice(text: &str, mut edits: Vec<(usize, usize, String)>) -> String {
    edits.sort_by_key(|e| std::cmp::Reverse(e.0));
    let mut out = text.to_string();
    for (start, end, replacement) in edits {
        out.replace_range(start..end, &replacement);
    }
    out
}

/// Picks the prefix to use for `ns` in `desc`, and the declaration to add if
/// it isn't already bound.
fn prefix_for(desc: &Desc, ns: &str, wanted: &str) -> (String, Option<String>) {
    if let Some((p, _)) = desc.scope.iter().rev().find(|(p, uri)| uri == ns && !p.is_empty() && resolve(&desc.scope, p) == Some(ns)) {
        return (p.clone(), None);
    }
    let mut prefix = wanted.to_string();
    let mut n = 1;
    while resolve(&desc.scope, &prefix).is_some() {
        prefix = format!("{wanted}{n}");
        n += 1;
    }
    let decl = format!("xmlns:{prefix}=\"{ns}\"");
    (prefix, Some(decl))
}

fn set_simple(text: &str, ns: &str, local: &str, wanted_prefix: &str, value: Option<&str>) -> Result<String, String> {
    let doc = Doc::scan(text)?;
    let existing: Vec<&Prop> = doc.find(ns, local).collect();
    let mut edits = Vec::new();

    match (value, existing.split_first()) {
        (Some(v), Some((first, rest))) => {
            edits.push((first.inner.0, first.inner.1, escape(v)));
            edits.extend(rest.iter().map(|p| (p.span.0, p.span.1, String::new())));
        }
        (Some(v), None) => {
            if doc.descs.is_empty() {
                let close = doc.rdf_close.ok_or("rdf:RDF has no room for a description")?;
                let (rdf_desc, about) = (doc.rdf_tag("Description"), doc.rdf_tag("about"));
                let new = format!(
                    " <{rdf_desc} {about}=\"\" xmlns:{wanted_prefix}=\"{ns}\" {wanted_prefix}:{local}=\"{}\"/>\n",
                    escape(v)
                );
                edits.push((close, close, new));
            } else {
                // Prefer a description that already knows the namespace.
                let desc = doc
                    .descs
                    .iter()
                    .find(|d| d.scope.iter().any(|(_, uri)| uri == ns))
                    .unwrap_or(&doc.descs[0]);
                let (prefix, decl) = prefix_for(desc, ns, wanted_prefix);
                let sep = &desc.attr_sep;
                let mut new = String::new();
                if let Some(decl) = decl {
                    new.push_str(&format!("{sep}{decl}"));
                }
                new.push_str(&format!("{sep}{prefix}:{local}=\"{}\"", escape(v)));
                edits.push((desc.attr_at, desc.attr_at, new));
            }
        }
        (None, _) => edits.extend(existing.iter().map(|p| (p.span.0, p.span.1, String::new()))),
    }
    Ok(splice(text, edits))
}

fn bag(doc: &Doc, keywords: &[String], indent: &str) -> String {
    let (bag, li) = (doc.rdf_tag("Bag"), doc.rdf_tag("li"));
    let mut out = format!("\n{indent} <{bag}>\n");
    for k in keywords {
        out.push_str(&format!("{indent}  <{li}>{}</{li}>\n", escape(k)));
    }
    out.push_str(&format!("{indent} </{bag}>\n{indent}"));
    out
}

fn set_keywords(text: &str, keywords: &[String]) -> Result<String, String> {
    let doc = Doc::scan(text)?;
    let existing: Vec<&Prop> = doc.find(NS_DC, "subject").collect();
    let mut edits = Vec::new();

    if keywords.is_empty() {
        edits.extend(existing.iter().map(|p| (p.span.0, p.span.1, String::new())));
        return Ok(splice(text, edits));
    }

    // An element we can refill in place, if there is one.
    let target = existing.iter().find(|p| !p.is_attr && p.inner.0 != p.inner.1);
    edits.extend(
        existing
            .iter()
            .filter(|p| target.is_none_or(|t| t.span != p.span))
            .map(|p| (p.span.0, p.span.1, String::new())),
    );
    if let Some(prop) = target {
        let line = text[..prop.inner.0].rfind('\n').map_or(0, |i| i + 1);
        let indent: String = text[line..].chars().take_while(|c| *c == ' ' || *c == '\t').collect();
        edits.push((prop.inner.0, prop.inner.1, bag(&doc, keywords, &indent)));
    } else if let Some((desc, close)) = doc.descs.iter().find_map(|d| d.close.map(|c| (d, c))) {
        let (prefix, decl) = prefix_for(desc, NS_DC, "dc");
        let decl = decl.map(|d| format!(" {d}")).unwrap_or_default();
        let at = text[..close].trim_end_matches([' ', '\t', '\r', '\n']).len();
        let indent = "   ";
        let new = format!("\n{indent}<{prefix}:subject{decl}>{}</{prefix}:subject>", bag(&doc, keywords, indent));
        edits.push((at, at, new));
    } else {
        // Only self-closing descriptions: XMP allows several per packet, as
        // long as they share an `rdf:about`.
        let close = doc.rdf_close.ok_or("rdf:RDF has no room for a description")?;
        let about = doc.descs.first().map_or("", |d| d.about.as_str());
        let new = format!(
            " <{d} {a}=\"{about}\" xmlns:dc=\"{NS_DC}\">\n  <dc:subject>{}</dc:subject>\n </{d}>\n",
            bag(&doc, keywords, "  "),
            d = doc.rdf_tag("Description"),
            a = doc.rdf_tag("about"),
        );
        edits.push((close, close, new));
    }
    Ok(splice(text, edits))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// As Camera Raw writes it: attributes, nested descriptions, padding.
    const ADOBE: &str = concat!(
        "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n",
        r#"<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:xmp="http://ns.adobe.com/xap/1.0/"
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
    xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/"
    xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
    xmlns:dc="http://purl.org/dc/elements/1.1/"
   xmp:Rating="3"
   xmp:Label="Select"
   photoshop:LabelColor="Red"
   crs:Exposure2012="+0.35"
   crs:Contrast2012="-12">
   <crs:Look>
    <rdf:Description crs:Name="Adobe Color" xmp:Rating="1" xmp:Label="Nested">
     <crs:Parameters>
      <rdf:Description crs:Version="15.0"/>
     </crs:Parameters>
    </rdf:Description>
   </crs:Look>
   <xmpMM:Pantry>
    <rdf:Bag>
     <rdf:li>
      <rdf:Description xmp:Rating="5">
       <dc:subject><rdf:Bag><rdf:li>pantry</rdf:li></rdf:Bag></dc:subject>
      </rdf:Description>
     </rdf:li>
    </rdf:Bag>
   </xmpMM:Pantry>
   <dc:subject>
    <rdf:Bag>
     <rdf:li>beach</rdf:li>
     <rdf:li>sunset &amp; sea</rdf:li>
    </rdf:Bag>
   </dc:subject>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
                                                                 
<?xpacket end="w"?>"#
    );

    fn rating(r: Option<i8>) -> Change {
        Change { rating: Some(r), ..Default::default() }
    }

    fn label(l: Option<&str>) -> Change {
        Change { label: Some(l.map(String::from)), ..Default::default() }
    }

    fn keywords(k: &[&str]) -> Change {
        Change { keywords: Some(k.iter().map(|s| s.to_string()).collect()), ..Default::default() }
    }

    #[test]
    fn reads_top_level_fields_and_ignores_nested_descriptions() {
        let f = parse(ADOBE).unwrap();
        assert_eq!(f.rating, Some(3));
        assert_eq!(f.label.as_deref(), Some("Select"));
        assert_eq!(f.label_color.as_deref(), Some("Red"));
        assert_eq!(f.keywords, ["beach", "sunset & sea"]);
    }

    #[test]
    fn a_rating_edit_changes_one_character_and_nothing_else() {
        let out = apply(ADOBE, &rating(Some(5))).unwrap();
        assert_eq!(out, ADOBE.replacen("xmp:Rating=\"3\"", "xmp:Rating=\"5\"", 1));
    }

    #[test]
    fn keyword_and_label_edits_preserve_every_unknown_field() {
        let out = apply(ADOBE, &keywords(&["beach", "new"])).unwrap();
        let out = apply(&out, &label(Some("Approved"))).unwrap();
        for kept in ["crs:Exposure2012=\"+0.35\"", "crs:Contrast2012=\"-12\"", "<crs:Look>", "xmp:Label=\"Nested\"", "pantry", "x:xmptk=\"Adobe XMP Core 7.0\"", "<?xpacket end=\"w\"?>"] {
            assert!(out.contains(kept), "lost {kept}");
        }
        let f = parse(&out).unwrap();
        assert_eq!(f.keywords, ["beach", "new"]);
        assert_eq!(f.label.as_deref(), Some("Approved"));
        assert_eq!(f.label_color.as_deref(), Some("Red"), "only the caller decides about LabelColor");
    }

    #[test]
    fn removing_fields_removes_only_those_fields() {
        let cleared = Change {
            rating: Some(None),
            label: Some(None),
            label_color: Some(None),
            keywords: Some(vec![]),
        };
        let out = apply(ADOBE, &cleared).unwrap();
        assert_eq!(parse(&out).unwrap(), Fields::default());
        assert!(!out.contains("xmp:Rating=\"3\""));
        assert!(out.contains("xmp:Rating=\"1\"") && out.contains("<crs:Look>"));
    }

    #[test]
    fn adds_fields_to_a_description_that_has_none() {
        let minimal = r#"<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:Exposure2012="+1"/></rdf:RDF></x:xmpmeta>"#;
        let change = Change {
            rating: Some(Some(4)),
            label: Some(Some("Green".into())),
            label_color: None,
            keywords: Some(vec!["a".into()]),
        };
        let out = apply(minimal, &change).unwrap();
        let f = parse(&out).unwrap();
        assert_eq!((f.rating, f.label.as_deref(), f.keywords.len()), (Some(4), Some("Green"), 1));
        assert!(out.contains("crs:Exposure2012=\"+1\""));
    }

    #[test]
    fn element_form_and_other_prefixes_are_found_by_namespace() {
        let text = r#"<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about="" xmlns:xap="http://ns.adobe.com/xap/1.0/" xmlns:d="http://purl.org/dc/elements/1.1/">
   <xap:Rating>2</xap:Rating>
   <xap:Label>To Do</xap:Label>
   <d:subject><rdf:Seq><rdf:li>one</rdf:li></rdf:Seq></d:subject>
  </rdf:Description>
 </rdf:RDF>"#;
        let f = parse(text).unwrap();
        assert_eq!((f.rating, f.label.as_deref()), (Some(2), Some("To Do")));
        assert_eq!(f.keywords, ["one"]);
        let out = apply(text, &rating(Some(4))).unwrap();
        assert!(out.contains("<xap:Rating>4</xap:Rating>"));
        let out = apply(&out, &rating(None)).unwrap();
        assert!(!out.contains("Rating") && parse(&out).unwrap().label.as_deref() == Some("To Do"));
    }

    #[test]
    fn a_taken_prefix_is_not_reused_for_the_wrong_namespace() {
        let text = r#"<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xmp="urn:other"/></rdf:RDF>"#;
        let out = apply(text, &rating(Some(2))).unwrap();
        assert!(out.contains("xmlns:xmp1=\"http://ns.adobe.com/xap/1.0/\""));
        assert_eq!(parse(&out).unwrap().rating, Some(2));
    }

    #[test]
    fn empty_and_odd_ratings() {
        let with = |r: &str| {
            format!(r#"<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="{r}"/></rdf:RDF>"#)
        };
        for (raw, want) in [("", None), ("  ", None), ("0", None), ("abc", None), ("9", None), ("-1", Some(-1)), ("4", Some(4)), ("3.0", Some(3))] {
            assert_eq!(parse(&with(raw)).unwrap().rating, want, "rating {raw:?}");
        }
        // An empty rating can be overwritten and cleared like any other.
        let out = apply(&with(""), &rating(Some(3))).unwrap();
        assert_eq!(parse(&out).unwrap().rating, Some(3));
        assert_eq!(out.matches("Rating").count(), 1);
    }

    #[test]
    fn unicode_and_markup_in_keywords_round_trip() {
        let words = ["Zoë", "東京", "🌅 sunset", "a<b>&\"c'", "Ñandú"];
        let out = apply(ADOBE, &keywords(&words)).unwrap();
        assert_eq!(parse(&out).unwrap().keywords, words);
        let fresh = new_packet(&Fields { keywords: words.iter().map(|s| s.to_string()).collect(), ..Default::default() }).unwrap();
        assert_eq!(parse(&fresh).unwrap().keywords, words);
    }

    #[test]
    fn new_packets_carry_all_fields() {
        let fields = Fields {
            rating: Some(4),
            label: Some("Rock & Roll".into()),
            label_color: None,
            keywords: vec!["x".into()],
        };
        assert_eq!(parse(&new_packet(&fields).unwrap()).unwrap(), fields);
        assert_eq!(parse(&new_packet(&Fields::default()).unwrap()).unwrap(), Fields::default());
    }

    #[test]
    fn malformed_packets_are_errors_never_panics() {
        let truncated = &ADOBE[..ADOBE.len() / 2];
        let cases = [
            "",
            "   ",
            "not xml at all",
            "<a><b></a></b>",
            "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"></x:xmpmeta>",
            "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description",
            "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description a=\"1\" a=\"2\"/></rdf:RDF>",
            "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"/>trailing",
            truncated,
        ];
        for text in cases {
            assert!(parse(text).is_err(), "should reject {text:?}");
            assert!(apply(text, &rating(Some(1))).is_err(), "should refuse to edit {text:?}");
        }
        assert!(parse_bytes(&[0xFF, 0xFE, b'<', 0]).is_err());
    }

    #[test]
    fn a_bom_is_kept_and_no_change_means_no_change() {
        let text = format!("\u{FEFF}{ADOBE}");
        assert_eq!(apply(&text, &rating(Some(3))).unwrap(), text);
        assert!(apply(&text, &rating(Some(1))).unwrap().starts_with('\u{FEFF}'));
    }
}
