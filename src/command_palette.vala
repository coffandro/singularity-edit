using GLib;
using Gtk;

namespace Singularity.Apps {

    public delegate void PaletteAction ();

    public class CommandPaletteItem : Object {
        public string  icon_name;
        public string  title;
        public string? subtitle;
        public string? hotkey;
        public string  category;
        public PaletteAction action;

        public CommandPaletteItem (string icon_name, string title, string? subtitle,
                                   string? hotkey, string category,
                                   owned PaletteAction action) {
            this.icon_name = icon_name;
            this.title     = title;
            this.subtitle  = subtitle;
            this.hotkey    = hotkey;
            this.category  = category;
            this.action    = (owned) action;
        }
    }

    /**
     * Thin wrapper around `Singularity.Widgets.OverlaySearch` that adds the
     * "execute a callback when the row is picked" behaviour expected by the
     * editor. The visual / filtering / keyboard handling is in the shared
     * widget; this class only holds the action dispatch table.
     */
    public class CommandPalette : Box {
        public signal void close_requested ();

        private Singularity.Widgets.OverlaySearch _search;
        private HashTable<string, CommandPaletteItem> _items;

        public CommandPalette () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            // Stay invisible (and so non-hit-testable inside Gtk.Overlay)
            // until explicitly opened. Same for the inner search widget.
            hexpand = false;
            vexpand = false;
            halign  = Align.FILL;
            valign  = Align.FILL;
            visible = false;
            // Stop pointer events that miss the inner card from reaching
            // the content underneath while we're open.
            can_target = false;

            _items = new HashTable<string, CommandPaletteItem> (str_hash, str_equal);

            _search = new Singularity.Widgets.OverlaySearch ();
            _search.placeholder = "Type a command or file…";
            _search.close_requested.connect (() => close_requested ());
            _search.item_activated.connect ((id) => {
                close_requested ();
                var it = _items.lookup (id);
                if (it != null) it.action ();
            });
            append (_search);
        }

        public void set_items (CommandPaletteItem[] items) {
            _items.remove_all ();
            var converted = new Singularity.Widgets.OverlaySearchItem[items.length];
            for (int i = 0; i < items.length; i++) {
                string id = i.to_string ();
                _items.insert (id, items[i]);
                converted[i] = new Singularity.Widgets.OverlaySearchItem (
                    id, items[i].icon_name, items[i].title,
                    items[i].subtitle, items[i].hotkey, items[i].category);
            }
            _search.set_items (converted);
        }

        public void open ()  {
            visible    = true;
            can_target = true;
            _search.open ();
        }
        public void close () {
            _search.close ();
            visible    = false;
            can_target = false;
        }
    }
}
