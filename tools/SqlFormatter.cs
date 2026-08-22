using System;
using System.Collections.Generic;
using System.Text;

public enum SegType { Code, Str, LineComment, BlockComment, Bracket }

public class Segment
{
    public SegType Type;
    public string Text;
}

public static class SqlFormatter
{
    // Tokenize into segments; concatenation of Text fields reproduces the original string exactly.
    public static List<Segment> Tokenize(string s)
    {
        var segs = new List<Segment>();
        int i = 0, n = s.Length;
        var sb = new StringBuilder();
        SegType cur = SegType.Code;

        Action<SegType> flush = (t) =>
        {
            if (sb.Length > 0) { segs.Add(new Segment { Type = t, Text = sb.ToString() }); sb.Clear(); }
        };

        while (i < n)
        {
            char c = s[i];
            if (cur == SegType.Code)
            {
                if (c == '\'') { flush(SegType.Code); cur = SegType.Str; sb.Append(c); i++; continue; }
                if (c == '[') { flush(SegType.Code); cur = SegType.Bracket; sb.Append(c); i++; continue; }
                if (c == '-' && i + 1 < n && s[i + 1] == '-') { flush(SegType.Code); cur = SegType.LineComment; sb.Append(c); sb.Append(s[i + 1]); i += 2; continue; }
                if (c == '/' && i + 1 < n && s[i + 1] == '*') { flush(SegType.Code); cur = SegType.BlockComment; sb.Append(c); sb.Append(s[i + 1]); i += 2; continue; }
                sb.Append(c); i++; continue;
            }
            else if (cur == SegType.Str)
            {
                sb.Append(c);
                if (c == '\'')
                {
                    if (i + 1 < n && s[i + 1] == '\'') { sb.Append(s[i + 1]); i += 2; continue; }
                    i++; flush(SegType.Str); cur = SegType.Code; continue;
                }
                i++; continue;
            }
            else if (cur == SegType.Bracket)
            {
                sb.Append(c);
                if (c == ']') { i++; flush(SegType.Bracket); cur = SegType.Code; continue; }
                i++; continue;
            }
            else if (cur == SegType.LineComment)
            {
                if (c == '\r' || c == '\n') { flush(SegType.LineComment); cur = SegType.Code; continue; }
                sb.Append(c); i++; continue;
            }
            else // BlockComment
            {
                sb.Append(c);
                if (c == '*' && i + 1 < n && s[i + 1] == '/') { sb.Append(s[i + 1]); i += 2; flush(SegType.BlockComment); cur = SegType.Code; continue; }
                i++; continue;
            }
        }
        flush(cur);
        return segs;
    }

    static bool IsWordChar(char c) { return char.IsLetterOrDigit(c) || c == '_' || c == '@' || c == '#'; }

    // Matches keyword as a whole word at position i in s (case-sensitive, exact-case match as used in this codebase).
    static bool MatchKeyword(string s, int i, string kw)
    {
        if (i + kw.Length > s.Length) return false;
        if (string.CompareOrdinal(s, i, kw, 0, kw.Length) != 0) return false;
        if (i > 0 && IsWordChar(s[i - 1])) return false;
        int after = i + kw.Length;
        if (after < s.Length && IsWordChar(s[after])) return false;
        return true;
    }

    // ---- STEP 1: whitespace-normalize the Code segments only (tabs for indentation, single-space elsewhere) ----
    public static string NormalizeWhitespace(string original)
    {
        var segs = Tokenize(original);
        var outp = new StringBuilder();
        bool atLineStart = true; // true at very start of file and right after any '\n' we emit (any segment type)

        foreach (var seg in segs)
        {
            if (seg.Type != SegType.Code)
            {
                outp.Append(seg.Text);
                if (seg.Text.Length > 0) atLineStart = seg.Text[seg.Text.Length - 1] == '\n';
                continue;
            }

            string t = seg.Text;
            int i = 0, n = t.Length;
            while (i < n)
            {
                char c = t[i];
                if (c == '\r') { i++; continue; } // drop bare CR, we'll re-add CRLF at the very end
                if (c == '\n')
                {
                    // trim any trailing whitespace already appended on this line
                    while (outp.Length > 0 && (outp[outp.Length - 1] == ' ' || outp[outp.Length - 1] == '\t'))
                        outp.Length--;
                    outp.Append('\n');
                    atLineStart = true;
                    i++;
                    continue;
                }
                if (c == ' ' || c == '\t')
                {
                    int j = i;
                    while (j < n && (t[j] == ' ' || t[j] == '\t')) j++;
                    // peek: is the run followed immediately by end-of-line (in this segment or next)?
                    bool followedByNewline = (j < n && t[j] == '\r') || (j < n && t[j] == '\n');
                    if (atLineStart)
                    {
                        if (!followedByNewline)
                        {
                            // Walk the run preserving any pre-existing tab 1:1 (it already represents a
                            // full level - dividing it together with spaces by 4 would corrupt it) and
                            // only /4-converting maximal runs of plain spaces.
                            int k = i;
                            int spaceRun = 0;
                            Action flushSpaces = () =>
                            {
                                for (int q = 0; q < spaceRun / 4; q++) outp.Append('\t');
                                for (int q = 0; q < spaceRun % 4; q++) outp.Append(' ');
                                spaceRun = 0;
                            };
                            while (k < j)
                            {
                                if (t[k] == '\t') { flushSpaces(); outp.Append('\t'); }
                                else spaceRun++;
                                k++;
                            }
                            flushSpaces();
                        }
                        // if followed by newline it's a blank line - emit nothing
                    }
                    else
                    {
                        if (!followedByNewline) outp.Append(' ');
                    }
                    i = j;
                    continue;
                }
                outp.Append(c);
                atLineStart = false;
                i++;
            }
        }
        return outp.ToString();
    }

    // ---- STEP 2: split "; SET " (statement-level, Code-state only) onto a new line, same indentation ----
    public static string SplitCombinedSet(string s)
    {
        var segs = Tokenize(s);
        var outp = new StringBuilder();
        foreach (var seg in segs)
        {
            if (seg.Type != SegType.Code) { outp.Append(seg.Text); continue; }
            string t = seg.Text;
            int i = 0, n = t.Length;
            while (i < n)
            {
                if (t[i] == ';' && i + 1 < n && t[i + 1] == ' ' && MatchKeyword(t, i + 2, "SET"))
                {
                    string indent = CurrentLineIndent(outp); // capture BEFORE appending the newline
                    outp.Append(';');
                    outp.Append('\n');
                    outp.Append(indent);
                    i += 2; // skip ';' and the single space; loop continues at 'SET'
                    continue;
                }
                outp.Append(t[i]);
                i++;
            }
        }
        return outp.ToString();
    }

    static string CurrentLineIndent(StringBuilder sb)
    {
        int i = sb.Length - 1;
        while (i >= 0 && sb[i] != '\n') i--;
        int start = i + 1;
        int j = start;
        while (j < sb.Length && (sb[j] == '\t' || sb[j] == ' ')) j++;
        return sb.ToString(start, j - start);
    }

    // ---- STEP 3: FROM always starts a new line (unless already at line start) ----
    public static string SplitFromOntoOwnLine(string s)
    {
        var segs = Tokenize(s);
        var outp = new StringBuilder();
        foreach (var seg in segs)
        {
            if (seg.Type != SegType.Code) { outp.Append(seg.Text); continue; }
            string t = seg.Text;
            int i = 0, n = t.Length;
            while (i < n)
            {
                if (MatchKeyword(t, i, "FROM") && !AtLineStart(outp))
                {
                    string indent = CurrentIndentOfPrecedingLine(outp); // capture BEFORE appending the newline
                    // trim single trailing space before FROM if present
                    if (outp.Length > 0 && outp[outp.Length - 1] == ' ') outp.Length--;
                    outp.Append('\n');
                    outp.Append(indent);
                }
                outp.Append(t[i]);
                i++;
            }
        }
        return outp.ToString();
    }

    // ---- STEP 3b: JOIN/CROSS APPLY/OUTER APPLY continuation lines re-indented to match the level of the
    // FIRST TABLE after FROM (one level deeper than FROM itself - the convention already used throughout the
    // source), not FROM's own level. Source sometimes visually aligns them with extra spaces under the table
    // name instead, which doesn't map to a clean tab run. ----
    public static string NormalizeJoinContinuationIndent(string s)
    {
        var segs = Tokenize(s);
        var outp = new StringBuilder();
        string joinReferenceIndent = null; // indent level JOIN-type lines should be forced to
        bool awaitingTableIndent = false;  // true right after FROM, until the first non-JOIN continuation line is seen
        string fromIndent = null;
        bool atLineStart = true;
        foreach (var seg in segs)
        {
            if (seg.Type != SegType.Code)
            {
                outp.Append(seg.Text);
                if (seg.Text.Length > 0) atLineStart = seg.Text[seg.Text.Length - 1] == '\n';
                continue;
            }
            string t = seg.Text;
            int i = 0, n = t.Length;
            while (i < n)
            {
                char c = t[i];
                if (c == '\n') { outp.Append(c); atLineStart = true; i++; continue; }
                if (atLineStart && (c == ' ' || c == '\t'))
                {
                    int j = i;
                    while (j < n && (t[j] == ' ' || t[j] == '\t')) j++;
                    string origIndent = t.Substring(i, j - i);
                    bool isFrom = MatchKeyword(t, j, "FROM");
                    bool isJoinKw = MatchKeyword(t, j, "INNER") || MatchKeyword(t, j, "LEFT") || MatchKeyword(t, j, "RIGHT")
                        || MatchKeyword(t, j, "FULL") || MatchKeyword(t, j, "CROSS") || MatchKeyword(t, j, "OUTER") || MatchKeyword(t, j, "JOIN");
                    if (isFrom)
                    {
                        fromIndent = origIndent;
                        awaitingTableIndent = true;
                        outp.Append(origIndent);
                    }
                    else if (isJoinKw && awaitingTableIndent)
                    {
                        // FROM and the first table were on the same source line - no separate table-only
                        // line exists to take the reference from, so fall back to FROM's own level.
                        joinReferenceIndent = fromIndent;
                        awaitingTableIndent = false;
                        outp.Append(joinReferenceIndent ?? origIndent);
                    }
                    else if (isJoinKw && joinReferenceIndent != null)
                    {
                        outp.Append(joinReferenceIndent);
                    }
                    else
                    {
                        if (awaitingTableIndent) { joinReferenceIndent = origIndent; awaitingTableIndent = false; }
                        outp.Append(origIndent);
                    }
                    atLineStart = false;
                    i = j;
                    continue;
                }
                outp.Append(c);
                atLineStart = false;
                i++;
            }
        }
        return outp.ToString();
    }

    static bool AtLineStart(StringBuilder sb)
    {
        int i = sb.Length - 1;
        while (i >= 0 && (sb[i] == '\t' || sb[i] == ' ')) i--;
        return i < 0 || sb[i] == '\n';
    }

    // indent level of the line currently being written (the line containing content before the cursor)
    static string CurrentIndentOfPrecedingLine(StringBuilder sb)
    {
        int i = sb.Length - 1;
        while (i >= 0 && sb[i] != '\n') i--;
        int start = i + 1;
        int j = start;
        while (j < sb.Length && (sb[j] == '\t' || sb[j] == ' ')) j++;
        return sb.ToString(start, j - start);
    }

    // ---- STEP 4: WHERE clause formatting (single condition inline, multi condition split with WHERE alone) ----
    // ---- STEP 5: UPDATE ... SET clause formatting (single column inline, multi column split with SET alone) ----
    // Both handled by a generic clause splitter that scans Code-state text with paren-depth tracking.
    public static string FormatClauses(string s)
    {
        var segs = Tokenize(s);
        // Flatten to a list of (isCode, char) is expensive; instead operate segment-by-segment while tracking
        // global paren depth across segments (depth only changes in Code segments, since '(' / ')' inside strings
        // or comments must NOT affect depth - and they won't, since we only scan Code segments for parens).
        var outp = new StringBuilder();
        int depth = 0;
        int pendingUpdateDepth = -1; // depth at which an UPDATE was seen whose SET clause hasn't been consumed yet
        var parenIndentStack = new List<string>(); // parenIndentStack[d-1] = indent of the line where the '(' taking depth to d was opened

        for (int segIdx = 0; segIdx < segs.Count; segIdx++)
        {
            var seg = segs[segIdx];
            if (seg.Type != SegType.Code) { outp.Append(seg.Text); continue; }
            string t = seg.Text;
            int i = 0, n = t.Length;
            while (i < n)
            {
                char c = t[i];
                if (c == '(') { parenIndentStack.Add(CurrentIndentOfPrecedingLine(outp)); depth++; outp.Append(c); i++; continue; }
                if (c == ')') { depth--; if (parenIndentStack.Count > 0) parenIndentStack.RemoveAt(parenIndentStack.Count - 1); outp.Append(c); i++; continue; }

                if (depth == 0 && MatchKeyword(t, i, "UPDATE"))
                {
                    pendingUpdateDepth = depth;
                    outp.Append("UPDATE"); i += 6;
                    continue;
                }
                if (depth == pendingUpdateDepth && c == ';')
                {
                    pendingUpdateDepth = -1; // statement ended without a column-SET (shouldn't normally happen)
                }

                if (MatchKeyword(t, i, "WHERE"))
                {
                    string enclosingIndent = depth > 0 && parenIndentStack.Count >= depth ? parenIndentStack[depth - 1] : null;
                    var span = ExtractClauseSpan(segs, segIdx, i, "WHERE", depth);
                    EmitWhereClause(outp, span, depth, enclosingIndent);
                    segIdx = span.EndSegIdx; i = span.EndOffset;
                    seg = segs[segIdx]; t = seg.Text; n = t.Length;
                    continue;
                }
                if (MatchKeyword(t, i, "SET") && depth == pendingUpdateDepth)
                {
                    pendingUpdateDepth = -1; // this SET consumes the pending UPDATE
                    string enclosingIndent = depth > 0 && parenIndentStack.Count >= depth ? parenIndentStack[depth - 1] : null;
                    var span = ExtractClauseSpan(segs, segIdx, i, "SET", depth);
                    EmitSetClause(outp, span, depth, enclosingIndent);
                    segIdx = span.EndSegIdx; i = span.EndOffset;
                    seg = segs[segIdx]; t = seg.Text; n = t.Length;
                    continue;
                }
                outp.Append(c); i++;
            }
        }
        return outp.ToString();
    }

    class ClauseSpan
    {
        public List<Segment> Parts = new List<Segment>(); // sequence of (isCode,text) covering keyword..end, keyword text stripped out (caller re-emits keyword)
        public int EndSegIdx;
        public int EndOffset;
        public string Terminator; // ")" ";" or a keyword name / "EOF"
    }

    // Extracts the clause body (everything after the keyword) up to: a top-level (relative to startDepth) occurrence
    // of ';', or keywords GROUP/ORDER/HAVING/WHERE(only when scanning SET)/FROM(only when scanning SET, i.e. UPDATE...FROM)/OUTPUT,
    // or depth dropping below startDepth (closing an enclosing paren, e.g. end of a subquery).
    static ClauseSpan ExtractClauseSpan(List<Segment> segs, int startSegIdx, int startOffset, string keyword, int startDepth)
    {
        var span = new ClauseSpan();
        int segIdx = startSegIdx;
        int i = startOffset + keyword.Length;
        int depth = startDepth;
        bool scanningSet = keyword == "SET";

        while (segIdx < segs.Count)
        {
            var seg = segs[segIdx];
            if (seg.Type != SegType.Code)
            {
                span.Parts.Add(new Segment { Type = seg.Type, Text = seg.Text });
                segIdx++; i = 0;
                continue;
            }
            string t = seg.Text;
            int partStart = i;
            while (i < t.Length)
            {
                char c = t[i];
                if (c == '(') { depth++; i++; continue; }
                if (c == ')')
                {
                    if (depth == startDepth)
                    {
                        span.Parts.Add(new Segment { Type = SegType.Code, Text = t.Substring(partStart, i - partStart) });
                        span.EndSegIdx = segIdx; span.EndOffset = i;
                        span.Terminator = ")";
                        return span;
                    }
                    depth--; i++; continue;
                }
                if (depth == startDepth && c == ';')
                {
                    span.Parts.Add(new Segment { Type = SegType.Code, Text = t.Substring(partStart, i - partStart) });
                    span.EndSegIdx = segIdx; span.EndOffset = i;
                    span.Terminator = ";";
                    return span;
                }
                if (depth == startDepth && (MatchKeyword(t, i, "GROUP") || MatchKeyword(t, i, "ORDER") || MatchKeyword(t, i, "HAVING")
                    || MatchKeyword(t, i, "UNION") || MatchKeyword(t, i, "INTERSECT") || MatchKeyword(t, i, "EXCEPT")
                    || (scanningSet && (MatchKeyword(t, i, "WHERE") || MatchKeyword(t, i, "FROM") || MatchKeyword(t, i, "OUTPUT")))))
                {
                    span.Parts.Add(new Segment { Type = SegType.Code, Text = t.Substring(partStart, i - partStart) });
                    span.EndSegIdx = segIdx; span.EndOffset = i;
                    span.Terminator = "KEYWORD";
                    return span;
                }
                i++;
            }
            span.Parts.Add(new Segment { Type = SegType.Code, Text = t.Substring(partStart, i - partStart) });
            segIdx++; i = 0;
        }
        span.EndSegIdx = segs.Count - 1;
        span.EndOffset = segs[segs.Count - 1].Text.Length;
        span.Terminator = "EOF";
        return span;
    }

    // Splits clause Parts into top-level items separated by commas (for SET) - depth-aware across the Parts' Code segments.
    static List<List<Segment>> SplitTopLevelByComma(List<Segment> parts)
    {
        var items = new List<List<Segment>>();
        var cur = new List<Segment>();
        int depth = 0;
        foreach (var p in parts)
        {
            if (p.Type != SegType.Code) { cur.Add(p); continue; }
            var sb = new StringBuilder();
            foreach (char c in p.Text)
            {
                if (c == '(') depth++;
                if (c == ')') depth--;
                if (c == ',' && depth == 0)
                {
                    sb.Length = TrimTrailingWs(sb);
                    if (sb.Length > 0) cur.Add(new Segment { Type = SegType.Code, Text = sb.ToString() });
                    sb.Clear();
                    items.Add(cur);
                    cur = new List<Segment>();
                    continue;
                }
                sb.Append(c);
            }
            if (sb.Length > 0) cur.Add(new Segment { Type = SegType.Code, Text = sb.ToString() });
        }
        items.Add(cur);
        return items;
    }

    static int TrimTrailingWs(StringBuilder sb)
    {
        int len = sb.Length;
        while (len > 0 && (sb[len - 1] == ' ' || sb[len - 1] == '\t' || sb[len - 1] == '\n' || sb[len - 1] == '\r')) len--;
        return len;
    }

    static string JoinParts(List<Segment> parts)
    {
        var sb = new StringBuilder();
        foreach (var p in parts) sb.Append(p.Text);
        return sb.ToString().Trim(' ', '\t', '\n', '\r');
    }

    // top-level AND/OR count (depth 0 relative to clause start) within Code parts of the WHERE body.
    // A BETWEEN's own "x AND y" is not a condition separator, so the AND that pairs with a preceding
    // top-level BETWEEN is excluded from the count.
    static int CountTopLevelAndOr(List<Segment> parts)
    {
        int depth = 0, count = 0, pendingBetween = 0;
        foreach (var p in parts)
        {
            if (p.Type != SegType.Code) continue;
            string t = p.Text;
            for (int i = 0; i < t.Length; i++)
            {
                char c = t[i];
                if (c == '(') depth++;
                else if (c == ')') depth--;
                else if (depth == 0 && MatchKeyword(t, i, "BETWEEN")) pendingBetween++;
                else if (depth == 0 && MatchKeyword(t, i, "AND"))
                {
                    if (pendingBetween > 0) pendingBetween--;
                    else count++;
                }
                else if (depth == 0 && MatchKeyword(t, i, "OR")) count++;
            }
        }
        return count;
    }

    // Splits WHERE body into top-level condition items at depth 0 AND/OR boundaries, keeping the AND/OR with the following item.
    // Returns each item as its own segment list (not a flattened string) so callers can detect embedded comments
    // and avoid collapsing them onto one line (which would let a '--' comment swallow trailing code).
    static List<List<Segment>> SplitTopLevelConditions(List<Segment> parts)
    {
        var items = new List<List<Segment>>();
        var cur = new List<Segment>();
        var sb = new StringBuilder();
        int depth = 0;
        int pendingBetween = 0; // an AND pairing with a preceding top-level BETWEEN is not a condition separator
        Action flushCode = () => { if (sb.Length > 0) { cur.Add(new Segment { Type = SegType.Code, Text = sb.ToString() }); sb.Clear(); } };
        for (int pi = 0; pi < parts.Count; pi++)
        {
            var p = parts[pi];
            if (p.Type != SegType.Code) { flushCode(); cur.Add(p); continue; }
            string t = p.Text;
            int i = 0;
            while (i < t.Length)
            {
                char c = t[i];
                if (c == '(') { depth++; sb.Append(c); i++; continue; }
                if (c == ')') { depth--; sb.Append(c); i++; continue; }
                if (depth == 0 && MatchKeyword(t, i, "BETWEEN")) { pendingBetween++; sb.Append("BETWEEN"); i += 7; continue; }
                if (depth == 0 && MatchKeyword(t, i, "AND") && pendingBetween > 0)
                {
                    pendingBetween--; sb.Append("AND"); i += 3; continue;
                }
                if (depth == 0 && (MatchKeyword(t, i, "AND") || MatchKeyword(t, i, "OR")))
                {
                    flushCode();
                    if (cur.Count > 0) items.Add(cur);
                    cur = new List<Segment>();
                    int kwLen = MatchKeyword(t, i, "AND") ? 3 : 2;
                    sb.Append(t.Substring(i, kwLen));
                    i += kwLen;
                    continue;
                }
                sb.Append(c); i++;
            }
        }
        flushCode();
        if (cur.Count > 0) items.Add(cur);
        return items;
    }

    static bool HasComment(List<Segment> parts)
    {
        foreach (var p in parts) if (p.Type == SegType.LineComment || p.Type == SegType.BlockComment) return true;
        return false;
    }

    static List<Segment> ExtractSubrange(List<Segment> item, int startSeg, int startOff, int endSeg, int endOff)
    {
        var result = new List<Segment>();
        for (int s = startSeg; s <= endSeg; s++)
        {
            var seg = item[s];
            if (seg.Type != SegType.Code) { result.Add(seg); continue; }
            string t = seg.Text;
            int from = (s == startSeg) ? startOff : 0;
            int to = (s == endSeg) ? endOff : t.Length;
            if (to > from) result.Add(new Segment { Type = SegType.Code, Text = t.Substring(from, to - from) });
        }
        return result;
    }

    // Detects "[AND|OR] ( ...inner... )" where the parens are the ENTIRE remainder of the item (nothing
    // trails the closing paren). Purely structural - does not require the inner content to itself contain
    // further nested parens; that decision belongs to the caller.
    static bool TryUnwrapParenGroup(List<Segment> item, out string keyword, out List<Segment> inner)
    {
        keyword = null; inner = null;
        int segIdx = 0, off = 0;

        Func<bool> skipWs = () =>
        {
            while (segIdx < item.Count && item[segIdx].Type == SegType.Code)
            {
                string t = item[segIdx].Text;
                while (off < t.Length && (t[off] == ' ' || t[off] == '\t' || t[off] == '\n' || t[off] == '\r')) off++;
                if (off < t.Length) return true;
                segIdx++; off = 0;
            }
            return segIdx < item.Count; // true if positioned at a non-Code segment (nothing to skip there)
        };

        if (!skipWs() || segIdx >= item.Count || item[segIdx].Type != SegType.Code) return false;
        string cur = item[segIdx].Text;
        if (MatchKeyword(cur, off, "AND")) { keyword = "AND"; off += 3; }
        else if (MatchKeyword(cur, off, "OR")) { keyword = "OR"; off += 2; }

        if (!skipWs() || segIdx >= item.Count || item[segIdx].Type != SegType.Code) return false;
        cur = item[segIdx].Text;
        if (off >= cur.Length || cur[off] != '(') return false;
        off++;
        int startSeg = segIdx, startOff = off;
        int depth = 1;

        while (true)
        {
            if (segIdx >= item.Count) return false; // unbalanced - bail out safely
            if (item[segIdx].Type != SegType.Code) { segIdx++; off = 0; continue; }
            string t = item[segIdx].Text;
            while (off < t.Length)
            {
                char c = t[off];
                if (c == '(') { depth++; off++; continue; }
                if (c == ')')
                {
                    depth--;
                    if (depth == 0)
                    {
                        inner = ExtractSubrange(item, startSeg, startOff, segIdx, off);
                        int checkSeg = segIdx, checkOff = off + 1;
                        while (checkSeg < item.Count)
                        {
                            if (item[checkSeg].Type == SegType.Code)
                            {
                                string tt = item[checkSeg].Text;
                                while (checkOff < tt.Length)
                                {
                                    char cc = tt[checkOff];
                                    if (cc != ' ' && cc != '\t' && cc != '\n' && cc != '\r') return false; // trailing content - not a clean single wrap
                                    checkOff++;
                                }
                            }
                            else return false; // trailing comment/string after the closing paren
                            checkSeg++; checkOff = 0;
                        }
                        return true;
                    }
                    off++; continue;
                }
                off++;
            }
            segIdx++; off = 0;
        }
    }

    // Recursively formats a WHERE condition item. An item that is (optionally AND/OR-prefixed) fully wrapped
    // by a single paren pair AND whose wrapped content is itself a compound condition (has a top-level
    // AND/OR) gets expanded: the keyword (if any) goes alone on its own line, "(" and ")" each get their own
    // line, and the content between them is recursively processed the same way. A simple wrap with no
    // top-level AND/OR inside (e.g. "(Id = @Id)") and a plain leaf condition both stay flattened on one line.
    //
    // isTopLevel is true only for the WHERE clause's own condition list (not itself inside any paren): there,
    // a keyword-less first item's paren stays at "indent" (matching where a plain unwrapped first condition
    // would sit). Anywhere else - a keyword-less item nested inside an already-open paren - the paren still
    // goes one level deeper than its container, because it is opening a new group regardless of whether a
    // keyword precedes it.
    static void EmitConditionItem(StringBuilder outp, List<Segment> item, string indent, bool isTopLevel)
    {
        string keyword; List<Segment> inner;
        if (TryUnwrapParenGroup(item, out keyword, out inner) && CountTopLevelAndOr(inner) > 0)
        {
            string parenLevel;
            if (keyword != null)
            {
                outp.Append('\n'); outp.Append(indent); outp.Append(keyword);
                parenLevel = indent + "    ";
            }
            else
            {
                parenLevel = isTopLevel ? indent : (indent + "    ");
            }
            outp.Append('\n'); outp.Append(parenLevel); outp.Append('(');
            foreach (var sub in SplitTopLevelConditions(inner)) EmitConditionItem(outp, sub, parenLevel, false);
            outp.Append('\n'); outp.Append(parenLevel); outp.Append(')');
        }
        else
        {
            outp.Append('\n'); outp.Append(indent);
            outp.Append(SafeFlatten(item));
        }
    }

    // Flattens a clause item onto one line, UNLESS it contains a comment - collapsing the newline that
    // terminates a '--' comment would let it silently swallow the rest of the line. In that case the
    // item is preserved verbatim (still gets tab-indentation from the final normalize pass).
    static string SafeFlatten(List<Segment> parts)
    {
        if (HasComment(parts)) return JoinParts(parts);
        return CollapseInternalNewlines(JoinParts(parts));
    }

    static void EmitWhereClause(StringBuilder outp, ClauseSpan span, int depth, string enclosingIndent)
    {
        int andOrCount = CountTopLevelAndOr(span.Parts);
        string indent = CurrentIndentOfPrecedingLine(outp);
        if (!AtLineStart(outp))
        {
            if (outp.Length > 0 && outp[outp.Length - 1] == ' ') outp.Length--;
            outp.Append('\n'); outp.Append(indent);
        }
        outp.Append("WHERE");
        if (andOrCount == 0)
        {
            outp.Append(' ');
            outp.Append(SafeFlatten(span.Parts));
            if (span.Terminator == "KEYWORD") { outp.Append('\n'); outp.Append(indent); }
        }
        else
        {
            var conditions = SplitTopLevelConditions(span.Parts);
            string deeper = indent + "    ";
            foreach (var cond in conditions) EmitConditionItem(outp, cond, deeper, true);
            if (span.Terminator == ")") { outp.Append('\n'); outp.Append(enclosingIndent ?? indent); }
            else if (span.Terminator == "KEYWORD") { outp.Append('\n'); outp.Append(indent); }
        }
    }

    static void EmitSetClause(StringBuilder outp, ClauseSpan span, int depth, string enclosingIndent)
    {
        var items = SplitTopLevelByComma(span.Parts);
        string indent = CurrentIndentOfPrecedingLine(outp);
        if (!AtLineStart(outp))
        {
            if (outp.Length > 0 && outp[outp.Length - 1] == ' ') outp.Length--;
            outp.Append('\n'); outp.Append(indent);
        }
        outp.Append("SET");
        if (items.Count <= 1)
        {
            outp.Append(' ');
            outp.Append(SafeFlatten(items.Count == 1 ? items[0] : new List<Segment>()));
            if (span.Terminator == "KEYWORD") { outp.Append('\n'); outp.Append(indent); }
        }
        else
        {
            string deeper = indent + "    ";
            for (int k = 0; k < items.Count; k++)
            {
                outp.Append('\n'); outp.Append(deeper);
                outp.Append(SafeFlatten(items[k]));
                if (k < items.Count - 1) outp.Append(',');
            }
            if (span.Terminator == ")") { outp.Append('\n'); outp.Append(enclosingIndent ?? indent); }
            else if (span.Terminator == "KEYWORD") { outp.Append('\n'); outp.Append(indent); }
        }
    }

    // within an already-extracted clause body, collapse any leftover internal newlines/indentation (from the
    // original multi-line formatting) down to single spaces, so re-flowing doesn't leave stray line breaks.
    static string CollapseInternalNewlines(string body)
    {
        var sb = new StringBuilder();
        bool lastWasSpace = false;
        foreach (char c in body)
        {
            if (c == '\n' || c == '\r' || c == '\t')
            {
                if (!lastWasSpace) { sb.Append(' '); lastWasSpace = true; }
                continue;
            }
            if (c == ' ')
            {
                if (!lastWasSpace) { sb.Append(' '); lastWasSpace = true; }
                continue;
            }
            sb.Append(c);
            lastWasSpace = false;
        }
        return sb.ToString().Trim();
    }

    // ---- Verification: protected segments must match exactly; Code segments must match after stripping ALL whitespace ----
    public static bool VerifyEquivalent(string original, string reformatted, out string reason)
    {
        var a = Tokenize(original);
        var b = Tokenize(reformatted);

        // A '--' line comment's trailing spaces (right before the newline that ends it) are legitimately
        // trimmed by the formatter's own newline-handling, same as trailing whitespace anywhere else in code -
        // harmless (invisible, no effect on the comment's meaning). Normalize that one case before comparing;
        // every other protected-segment byte must still match exactly.
        Func<Segment, string> protKey = seg =>
        {
            string text = seg.Type == SegType.LineComment ? seg.Text.TrimEnd(' ', '\t') : seg.Text;
            return seg.Type + "|" + text;
        };

        var aProt = new List<string>(); var bProt = new List<string>();
        var aCode = new StringBuilder(); var bCode = new StringBuilder();
        foreach (var seg in a)
        {
            if (seg.Type == SegType.Code) foreach (char c in seg.Text) { if (!char.IsWhiteSpace(c)) aCode.Append(c); }
            else aProt.Add(protKey(seg));
        }
        foreach (var seg in b)
        {
            if (seg.Type == SegType.Code) foreach (char c in seg.Text) { if (!char.IsWhiteSpace(c)) bCode.Append(c); }
            else bProt.Add(protKey(seg));
        }

        if (aProt.Count != bProt.Count)
        {
            reason = "Numero di segmenti protetti (stringhe/commenti/[identificatori]) diverso: " + aProt.Count + " vs " + bProt.Count;
            return false;
        }
        for (int i = 0; i < aProt.Count; i++)
        {
            if (aProt[i] != bProt[i])
            {
                reason = "Segmento protetto #" + i + " diverso.";
                return false;
            }
        }
        if (aCode.ToString() != bCode.ToString())
        {
            reason = "Contenuto di codice (a parte whitespace) diverso.";
            return false;
        }
        reason = null;
        return true;
    }

    public static string FormatAll(string original)
    {
        // All structural passes operate on space-based indentation (matching the original extraction style).
        // Tabs are introduced exactly once, in the final NormalizeWhitespace call, to avoid double-converting
        // already-tabbed runs (which would corrupt them back into single spaces).
        string s = original;
        s = SplitCombinedSet(s);
        s = SplitFromOntoOwnLine(s);
        s = NormalizeJoinContinuationIndent(s);
        s = FormatClauses(s);
        s = NormalizeWhitespace(s);
        return s;
    }
}
