# Align apps.txt into fixed-width columns separated by at least two spaces.
# Input cells may be separated by tabs or 2+ spaces; empty cells become "-".
# Usage: jq -Rrs -f scripts/format-apps.jq apps.txt

[split("\n")[] | select(test("\\S")) | gsub("^\\s+|\\s+$"; "") | [splits("\t| {2,}")]
 | map(gsub("^ +| +$"; "") | if . == "" then "-" else . end)] as $rows
| ($rows[0] | length) as $n
| if any($rows[]; length != $n) then
    error("every row needs \($n) columns: " + ([$rows[] | select(length != $n) | join(" | ")] | join("; ")))
  else . end
| [range($n) as $i | [$rows[][$i] | length] | max] as $w
| $rows[]
| [to_entries[] | .value + (" " * ($w[.key] - (.value | length)))]
| join("  ")
| sub(" +$"; "")
