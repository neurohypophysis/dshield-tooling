function in_range(ts) {
  return (start == "" || ts >= start) && (end == "" || ts <= end)
}

function fmt() {
  if (interval == "minute") return "+%Y-%m-%dT%H:%M"
  else if (interval == "hour") return "+%Y-%m-%dT%H"
  else if (interval == "day") return "+%Y-%m-%d"
  else if (interval == "month") return "+%Y-%m"
  else if (interval == "week") return "+%G-W%V"
}

function truncate_ts(ts,   cmd, out) {
  cmd = "date -u -d \"" ts "\" " fmt()
  cmd | getline out
  close(cmd)
  return out
}

function ts_for_date(ts) {
  sub(/Z$/, "", ts)
  if (ts ~ /^[0-9-]+T[0-9][0-9]:[0-9][0-9]$/) {
    ts = ts ":00"
  }
  return ts "Z"
}

function next_interval(ts,   cmd, out) {
  if (interval == "minute")
    cmd = "date -u -d \"" ts_for_date(ts) " +1 minute\" " fmt()
  else if (interval == "hour")
    cmd = "date -u -d \"" ts_for_date(ts) " +1 hour\" " fmt()
  else if (interval == "day")
    cmd = "date -u -d \"" ts_for_date(ts) " 00:00:00Z +1 day\" " fmt()
  else if (interval == "month")
    cmd = "date -u -d \"" ts_for_date(ts) "-01 00:00:00Z +1 month\" " fmt()
  else if (interval == "week")
    cmd = "date -u -d \"" ts_for_date(ts) " 00:00:00Z +7 day\" " fmt()

  cmd | getline out
  close(cmd)
  return out
}

{
  ts = $0
  if (in_range(ts)) {
    key = truncate_ts(ts)
    counts[key]++
  }
}

function normalize(ts) {
  if (interval == "minute") ts = ts ":00"
  else if (interval == "hour") ts = ts ":00:00"
  else if (interval == "day") ts = ts " 00:00:00"
  else if (interval == "month") ts = ts "-01 00:00:00"
  else if (interval == "week") ts = ts " 00:00:00"
  sub(/Z$/, "", ts)   # just in case
  return ts "Z"
}

function to_epoch(ts,   cmd, out) {
  ts = normalize(ts)
  cmd = "date -u -d \"" ts "\" +%s"
  if ((cmd | getline out) <= 0) {
    print "ERROR: to_epoch failed for ts=" ts > "/dev/stderr"
    close(cmd)
    return -1
  }
  close(cmd)
  return out
}

END {
  PROCINFO["sorted_in"] = "@ind_str_asc"

  first = last = ""
  for (k in counts) {
    if (first == "" || to_epoch(k) < to_epoch(first)) first = k
    if (last == "" || to_epoch(k) > to_epoch(last)) last = k
  }

  if (fill_empty == 1 && first != "" && last != "") {
    t = first
    while (to_epoch(t) <= to_epoch(last)) {
      if (!(t in counts)) counts[t] = 0

      old = t
      t = next_interval(t)

      if (t == old) {
        exit 1
      }
    }
  }

  if (nohist == 1) {
    for (k in counts) {
      print k "\t" counts[k]
    }
    exit
  }

  max_count = 0
  for (k in counts) if (counts[k] > max_count) max_count = counts[k]

  term_width = 80
  cmd = "tput cols"
  cmd | getline term_width
  close(cmd)

  label_width = 25
  bar_max_width = term_width - label_width
  if (bar_max_width < 10) bar_max_width = 10

  for (k in counts) {
    count = counts[k]
    bar_len = (max_count > 0 ? int((count / max_count) * bar_max_width) : 0)
    if (bar_len < 1 && count > 0) bar_len = 1
    bar = ""
    for (i = 0; i < bar_len; i++) bar = bar "#"
    printf "%-16s %5d %s\n", k, count, bar
  }
}
