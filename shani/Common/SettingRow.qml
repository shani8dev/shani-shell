// The common settings row: an icon, a title and subtitle on the left, and a
// trailing control (a switch, a button, a value) on the right — the shape the
// Settings pages repeat as ListRow + SwitchRow. The accessibility wiring and the
// search flash are ListRow's; `control` names the trailing slot so a row reads
// as "this label, this control". `interactive` and `selected` behave as ListRow.
import qs.Common

ListRow {
    id: root
    // the trailing control slot (ListRow's default); named for the call site
    property alias control: root.extra
}
