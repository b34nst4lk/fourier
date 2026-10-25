// The browser's calendar day, in the LOCAL timezone.
//
// The admin prefills a date field with "the next free day" (schedule.gleam), and
// "today" there means today where the human is sitting, not where the server
// runs. This date never crosses the wire: it is a prefill, and the backend keeps
// its own calendar for everything it must enforce (its dates.gleam).

export function today_local() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}
