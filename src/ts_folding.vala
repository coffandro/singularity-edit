using GLib;
using Gtk;

namespace Singularity.Apps {

    public struct FoldRegion {
        public int    start_line;     // inclusive, 0-based
        public int    end_line;       // inclusive, 0-based
        public uint32 start_byte;
        public uint32 end_byte;
    }

    /**
     * Computes fold regions from folds.scm and toggles them by applying an
     * invisible GtkTextTag from the end of the start line to the end of the
     * fold's end line. The first line of every fold remains visible so the
     * user can still read e.g. the function signature.
     */
    public class TsFolding : Object {
        public unowned GtkSource.Buffer buffer { get; private set; }
        public TsLanguageDef def { get; private set; }

        private Gtk.TextTag fold_tag;
        // Track folded ranges by (start_line, end_line) so we can rebuild them
        // after a reparse moves them.
        private GenericArray<FoldRegion?> folded;

        public TsFolding (GtkSource.Buffer buffer, TsLanguageDef def) {
            this.buffer = buffer;
            this.def    = def;
            this.folded = new GenericArray<FoldRegion?> ();

            var table = buffer.get_tag_table ();
            var existing = table.lookup ("ts:fold-hidden");
            if (existing != null) {
                fold_tag = existing;
            } else {
                fold_tag = buffer.create_tag ("ts:fold-hidden");
                fold_tag.invisible = true;
            }
        }

        public FoldRegion?[] compute (unowned TS.Tree tree) {
            unowned TS.Query? q = def.folds_query;
            if (q == null) return {};

            var qc = new TS.QueryCursor ();
            qc.exec (q, tree.root_node ());

            var arr = new GenericArray<FoldRegion?> ();
            TS.QueryMatch match;
            uint32 cap_idx;
            while (qc.next_capture (out match, out cap_idx)) {
                unowned TS.QueryCapture cap = match.captures[cap_idx];
                var sp = cap.node.start_point ();
                var ep = cap.node.end_point ();
                if ((int) ep.row <= (int) sp.row) continue; // single-line: nothing to fold
                arr.add ({ (int) sp.row, (int) ep.row,
                           cap.node.start_byte (), cap.node.end_byte () });
            }
            return arr.steal ();
        }

        //  apply / remove tag

        private void hide_range (int start_line, int end_line) {
            Gtk.TextIter s, e;
            buffer.get_iter_at_line (out s, start_line);
            // Hide from end of start_line through end of end_line. This keeps
            // the opening line visible.
            s.forward_to_line_end ();

            buffer.get_iter_at_line (out e, end_line);
            e.forward_to_line_end ();

            if (e.compare (s) > 0) buffer.apply_tag (fold_tag, s, e);
        }

        private void show_range (int start_line, int end_line) {
            Gtk.TextIter s, e;
            buffer.get_iter_at_line (out s, start_line);
            s.forward_to_line_end ();
            buffer.get_iter_at_line (out e, end_line);
            e.forward_to_line_end ();
            if (e.compare (s) > 0) buffer.remove_tag (fold_tag, s, e);
        }

        public void unfold_all () {
            Gtk.TextIter s, e;
            buffer.get_bounds (out s, out e);
            buffer.remove_tag (fold_tag, s, e);
            folded.remove_range (0, folded.length);
        }

        public bool toggle_at_line (int line, FoldRegion?[] regions) {
            // Find smallest region containing this line.
            FoldRegion? best = null;
            foreach (var r in regions) {
                if (r == null) continue;
                if (line >= r.start_line && line <= r.end_line) {
                    if (best == null || (r.end_line - r.start_line) <
                                        (best.end_line - best.start_line)) {
                        best = r;
                    }
                }
            }
            if (best == null) return false;

            // Already folded?
            int idx = -1;
            for (int i = 0; i < folded.length; i++) {
                if (folded[i].start_line == best.start_line &&
                    folded[i].end_line   == best.end_line) {
                    idx = i; break;
                }
            }
            if (idx >= 0) {
                show_range (best.start_line, best.end_line);
                folded.remove_index (idx);
            } else {
                hide_range (best.start_line, best.end_line);
                folded.add (best);
            }
            return true;
        }

        /**
         * Reapply known folded ranges to a freshly reparsed tree. Best-effort:
         * uses the existing (start_line, end_line) pairs since lines may have
         * shifted after edits.
         */
        public void reapply () {
            var snapshot = folded;
            folded = new GenericArray<FoldRegion?> ();
            foreach (var r in snapshot) {
                if (r == null) continue;
                hide_range (r.start_line, r.end_line);
                folded.add (r);
            }
        }
    }
}
