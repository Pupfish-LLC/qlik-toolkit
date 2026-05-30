#!/bin/bash
################################################################################
# validate-qvs-syntax.sh
#
# Qlik Script Validation Hook
#
# Purpose:
#   Detects high-confidence syntax errors in .qvs (Qlik script) files before
#   they reach execution validation gates. This hook scans for SQL constructs
#   that do not exist in Qlik LOAD context, unbalanced control blocks, and
#   malformed function arguments.
#
# Key Distinction - SQL Pass-Through vs LOAD Context:
#   Qlik scripts allow two contexts:
#   1. LOAD context: Native Qlik language (LOAD, RESIDENT, WHERE, etc.)
#   2. SQL pass-through: Direct SQL to database (SQL SELECT ... ;)
#
#   This hook ONLY flags SQL constructs in LOAD context. Constructs inside
#   SQL blocks (between "SQL" and ";") are legitimate and are EXCLUDED from checks.
#
# Critical SQL Constructs Not Allowed in Qlik LOAD Context:
#   - HAVING           (aggregate filtering; use preceding LOAD instead)
#   - Count(*)         (aggregation; use Count(field_name) instead)
#   - IS NULL/NOT NULL (null checking; use IsNull(field) function instead)
#   - BETWEEN          (range filtering; use >= AND <= instead)
#   - CASE WHEN        (conditional; use IF(), Pick(), Match() instead)
#   - IN (list)        (value matching; use Match() or WildMatch() instead)
#   - LIMIT            (row limiting; use WHERE RowNo() <= N instead)
#   - Table aliases    (FROM t1; use full table names in brackets instead)
#   - SELECT DISTINCT  (for LOAD context; use LOAD DISTINCT instead)
#
# Other Qlik Syntax Rules Checked:
#   - TRACE with embedded semicolon (terminates the statement early;
#     anything after the first ';' parses as a separate invalid statement)
#
# Checks Applied:
#   1. SQL Constructs in LOAD context
#   2. TRACE semicolon misuse
#   3. Block balance (IF/END IF, SUB/END SUB, FOR/NEXT)
#   4. PurgeChar() argument count validation
#
# Exit Codes:
#   0 = Normal completion (always, whether findings present or not). When run
#       as a PostToolUse hook, findings surface to Claude as advisory context
#       via a JSON object on stdout (hookSpecificOutput.additionalContext).
#       When run from the command line with file arguments, findings print as
#       plain text to stderr for human readers.
#   2 = Script-internal error (reserved; not currently emitted by main flow)
#
# Hook Output Protocol (PostToolUse):
#   Per https://code.claude.com/docs/en/hooks, PostToolUse hooks surface
#   advisory information to Claude via a JSON object on stdout with exit 0:
#     {
#       "hookSpecificOutput": {
#         "hookEventName": "PostToolUse",
#         "additionalContext": "<findings text>"
#       },
#       "systemMessage": "<short user-facing summary>"
#     }
#   No "decision" field is emitted — findings are advisory, never blocking.
#
# Usage:
#   ./validate-qvs-syntax.sh file.qvs
#   ./validate-qvs-syntax.sh scripts/*.qvs
################################################################################

set -u

# Colors for output (optional, may not be available in all shells)
WARN_PREFIX="[WARN]"

# Accumulate findings
findings=""
finding_count=0

# Track whether we were invoked as a PostToolUse hook (JSON on stdin) vs
# direct command-line invocation with file arguments. This determines the
# output format: structured JSON to stdout for hooks, plain text to stderr
# for humans.
invoked_as_hook=0

# Function to add a finding
add_finding() {
    local file="$1"
    local line="$2"
    local message="$3"

    if [ -z "$line" ]; then
        findings="${findings}${WARN_PREFIX} ${file}: ${message}"$'\n'
    else
        findings="${findings}${WARN_PREFIX} ${file}:${line}: ${message}"$'\n'
    fi
    finding_count=$((finding_count + 1))
}

# JSON-escape a string for safe embedding in a JSON string literal.
# Handles backslash, double quote, newline, carriage return, tab, and
# other ASCII control chars (escaped as \uXXXX). Uses jq when available
# for correctness; falls back to a sed pipeline that covers the same
# control characters when jq is not on PATH.
json_escape() {
    local raw="$1"
    if command -v jq &>/dev/null; then
        # -R reads raw input, -s slurps the whole stream, then encode as JSON.
        # Strip the surrounding quotes that jq adds so the caller controls placement.
        local encoded
        encoded=$(printf '%s' "$raw" | jq -Rs .)
        # Drop the leading and trailing double-quote that jq -Rs adds
        encoded="${encoded#\"}"
        encoded="${encoded%\"}"
        printf '%s' "$encoded"
    else
        # Fallback: escape the JSON-significant characters by hand.
        # Order matters: backslash MUST be escaped first.
        local s="$raw"
        s="${s//\\/\\\\}"      # \  -> \\
        s="${s//\"/\\\"}"      # "  -> \"
        s="${s//$'\n'/\\n}"    # LF -> \n
        s="${s//$'\r'/\\r}"    # CR -> \r
        s="${s//$'\t'/\\t}"    # TAB -> \t
        printf '%s' "$s"
    fi
}

# Process a single file
process_file() {
    local file="$1"

    # Check file exists and is readable
    if [ ! -f "$file" ]; then
        add_finding "$file" "" "File not found"
        return 2
    fi

    if [ ! -r "$file" ]; then
        add_finding "$file" "" "File not readable"
        return 2
    fi

    local line_num=0
    local in_sql=0
    local if_count=0
    local endif_count=0
    local sub_count=0
    local endsub_count=0
    local for_count=0
    local next_count=0

    # Read file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))

        # Handle CRLF line endings
        line="${line%$'\r'}"

        # Track SQL block boundaries (simplified state machine)
        # Check if entering SQL block (must start with SQL keyword)
        if echo "$line" | grep -iq '^\s*SQL\s'; then
            in_sql=1
        fi

        # Check if exiting SQL block (line contains semicolon terminator)
        # This can happen on the same line as "SQL" or on a later line
        if [ "$in_sql" -eq 1 ] && echo "$line" | grep -q ';'; then
            in_sql=0
            # Skip remaining checks for SQL terminator line
            continue
        fi

        # Skip checks inside SQL blocks (except terminator lines which we already skipped)
        if [ "$in_sql" -eq 1 ]; then
            continue
        fi

        # ===== SQL Construct Checks (LOAD context only) =====

        # 1. HAVING (case-insensitive, word boundaries)
        if echo "$line" | grep -iqE '\bHAVING\b'; then
            add_finding "$file" "$line_num" "SQL construct 'HAVING' found in LOAD context. Use preceding LOAD with filter instead."
        fi

        # 2. Count(*) - case insensitive, with asterisk
        if echo "$line" | grep -iqE '[Cc]ount\s*\(\s*\*\s*\)'; then
            add_finding "$file" "$line_num" "Count(*) not supported. Use Count(field_name) with explicit field reference."
        fi

        # 3. IS NULL or IS NOT NULL (case-insensitive, word boundaries)
        if echo "$line" | grep -iqE '\bIS\s+(NOT\s+)?NULL\b'; then
            # But not if it's the function IsNull()
            if ! echo "$line" | grep -iq 'IsNull('; then
                add_finding "$file" "$line_num" "'IS NULL' / 'IS NOT NULL' not supported in Qlik script. Use IsNull() function."
            fi
        fi

        # 4. BETWEEN (case-insensitive, word boundaries)
        if echo "$line" | grep -iqE '\bBETWEEN\b'; then
            add_finding "$file" "$line_num" "'BETWEEN' not supported. Use field >= low AND field <= high."
        fi

        # 5. CASE WHEN (both keywords present, case-insensitive)
        if echo "$line" | grep -iqE '\bCASE\b' && echo "$line" | grep -iqE '\bWHEN\b'; then
            add_finding "$file" "$line_num" "'CASE WHEN' not supported in Qlik LOAD. Use IF(), Pick(), or Match() instead."
        fi

        # 6. LIMIT (case-insensitive, word boundaries, followed by number)
        if echo "$line" | grep -iqE '\bLIMIT\s+[0-9]'; then
            add_finding "$file" "$line_num" "'LIMIT' not supported in Qlik LOAD. Use WHERE RowNo() <= N on a RESIDENT LOAD."
        fi

        # 7. IN (list) - pattern: IN followed by parentheses
        if echo "$line" | grep -iqE '\bIN\s*\('; then
            add_finding "$file" "$line_num" "'IN (list)' not supported. Use Match(field, val1, val2, ...) or WildMatch()."
        fi

        # 8. SELECT DISTINCT in LOAD context (not in SQL blocks, which are already skipped)
        if echo "$line" | grep -iqE 'SELECT\s+DISTINCT'; then
            add_finding "$file" "$line_num" "'SELECT DISTINCT' not allowed in LOAD context. Use 'LOAD DISTINCT' instead."
        fi

        # 9. TRACE with embedded semicolon
        # TRACE does not take a quoted argument; the first ';' terminates the
        # statement, and any subsequent text on the line parses as a separate
        # (usually invalid) statement, causing a reload error. A correct TRACE
        # line has exactly one ';' at the end.
        if echo "$line" | grep -iqE '^\s*TRACE\s'; then
            semi_count=$(echo "$line" | tr -cd ';' | wc -c)
            if [ "$semi_count" -gt 1 ]; then
                add_finding "$file" "$line_num" "TRACE statement contains $semi_count semicolons; the first ';' terminates the statement and anything after parses as an invalid statement. Replace embedded semicolons with commas, periods, or dashes."
            fi
        fi

        # ===== Block Balance Checks =====

        # Count IF THEN blocks (not IF() function calls)
        # Pattern: IF (word boundary) followed by THEN (not immediately followed by parenthesis)
        # This distinguishes control blocks "IF ... THEN" from function calls "IF(...)"
        if echo "$line" | grep -iqE '\bIF\s+(.*\s+)?THEN\b'; then
            if_count=$((if_count + 1))
        fi

        # Count END IF (case-insensitive, handles both "END IF" and "ENDIF")
        endif_line_count=$(echo "$line" | grep -io '\bEND\s*IF\b' | wc -l)
        endif_count=$((endif_count + endif_line_count))

        # Count SUB declarations (case-insensitive, word boundary start, followed by space/paren)
        # Avoid counting "sub" within other words; must be a standalone SUB keyword
        if echo "$line" | grep -iqE '^\s*SUB\s|^\s*SUB\('; then
            sub_count=$((sub_count + 1))
        fi

        # Count END SUB (case-insensitive)
        endsub_line_count=$(echo "$line" | grep -io '\bEND\s*SUB\b' | wc -l)
        endsub_count=$((endsub_count + endsub_line_count))

        # Count FOR (case-insensitive, word boundary)
        # Note: this pattern matches both bare 'FOR' and the 'FOR' in 'FOR EACH'.
        # Both control constructs close with NEXT, so a single counter is correct.
        for_line_count=$(echo "$line" | grep -io '\bFOR\b' | wc -l)
        for_count=$((for_count + for_line_count))

        # Count NEXT (case-insensitive, word boundary)
        next_line_count=$(echo "$line" | grep -io '\bNEXT\b' | wc -l)
        next_count=$((next_count + next_line_count))

        # ===== PurgeChar Argument Count Check =====

        # Find PurgeChar with single argument (no comma inside parentheses)
        # Pattern: PurgeChar\s*\([^,)]*\)
        if echo "$line" | grep -iqE '[Pp]urge[Cc]har\s*\([^,)]*\)'; then
            add_finding "$file" "$line_num" "PurgeChar() called with 1 argument (expected 2). Provide both text and chars_to_remove."
        fi

    done < "$file"

    # Check block balance after entire file is read
    if [ "$if_count" -ne "$endif_count" ]; then
        add_finding "$file" "" "Block imbalance: $if_count 'IF' found but $endif_count 'END IF' found. Check IF/END IF pairing."
    fi

    if [ "$sub_count" -ne "$endsub_count" ]; then
        add_finding "$file" "" "Block imbalance: $sub_count 'SUB' found but $endsub_count 'END SUB' found. Check SUB/END SUB pairing."
    fi

    # FOR and FOR EACH both close with NEXT; for_count already covers both
    # (the \bFOR\b pattern matches the leading FOR in 'FOR EACH').
    if [ "$for_count" -ne "$next_count" ]; then
        add_finding "$file" "" "Block imbalance: $for_count 'FOR/FOR EACH' found but $next_count 'NEXT' found. Check FOR/NEXT pairing."
    fi

    return 0
}

# Main: Determine file path from arguments or PostToolUse hook stdin
if [ $# -gt 0 ]; then
    # Direct invocation with file arguments
    files=("$@")
else
    # PostToolUse hook invocation: file path arrives as JSON on stdin.
    # Extract tool_input.file_path using jq (or grep fallback).
    invoked_as_hook=1
    hook_input=$(cat)
    if command -v jq &>/dev/null; then
        hook_file=$(echo "$hook_input" | jq -r '.tool_input.file_path // empty')
    else
        # Fallback: extract file_path with grep/sed if jq unavailable
        hook_file=$(echo "$hook_input" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
    fi

    if [ -z "${hook_file:-}" ]; then
        # No file path found in stdin or args; nothing to do.
        # Emit empty JSON object so Claude Code sees valid (no-op) hook output.
        echo '{}'
        exit 0
    fi
    files=("$hook_file")
fi

for file in "${files[@]}"; do
    # Only validate .qvs files; skip everything else silently
    case "$file" in
        *.qvs) process_file "$file" ;;
        *)     ;;
    esac
done

# Emit findings using the format that matches the invocation context.
if [ "$invoked_as_hook" -eq 1 ]; then
    # PostToolUse hook output: structured JSON on stdout, exit 0.
    # Per https://code.claude.com/docs/en/hooks, advisory findings surface
    # to Claude via hookSpecificOutput.additionalContext. A short
    # user-facing summary goes in the top-level systemMessage. No
    # "decision" field is emitted; findings are advisory, not blocking.
    if [ -n "$findings" ]; then
        # Strip any trailing newline so the rendered context is tight.
        findings_text="${findings%$'\n'}"
        escaped_findings=$(json_escape "$findings_text")
        summary="Qlik script validator flagged ${finding_count} finding(s); see additional context."
        escaped_summary=$(json_escape "$summary")
        printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"},"systemMessage":"%s"}\n' \
            "$escaped_findings" "$escaped_summary"
    else
        # Clean run — emit empty JSON object so Claude Code parses cleanly.
        echo '{}'
    fi
    exit 0
else
    # Direct command-line invocation: print findings to stderr for humans
    # so they surface in the terminal even when stdout is redirected, and
    # return a non-zero exit code so shell pipelines can detect findings.
    if [ -n "$findings" ]; then
        printf '%s' "$findings" >&2
        exit 1
    fi
    exit 0
fi
