using GLib;

namespace Singularity.Apps {

    public class TsLanguageDef {
        public string name;
        public unowned TS.Language language;
        public TS.Query? highlights_query;
        public TS.Query? folds_query;
        public TS.Query? locals_query;
        public bool queries_loaded;

        public TsLanguageDef (string name, TS.Language language) {
            this.name = name;
            this.language = language;
        }
    }

    public class TsLangRegistry : Object {
        private static TsLangRegistry? _instance;
        public static TsLangRegistry get_default () {
            if (_instance == null) _instance = new TsLangRegistry ();
            return _instance;
        }

        private HashTable<string, TsLanguageDef> by_ext;

        private TsLangRegistry () {
            by_ext = new HashTable<string, TsLanguageDef> (str_hash, str_equal);

            register ("go",         TSGrammars.go (),         { "go" });
            register ("rust",       TSGrammars.rust (),       { "rs" });
            register ("python",     TSGrammars.python (),     { "py", "pyi", "pyw" });
            register ("typescript", TSGrammars.typescript (), { "ts", "mts", "cts" });
            register ("tsx",        TSGrammars.tsx (),        { "tsx", "jsx" });
        }

        private void register (string name, TS.Language lang, string[] exts) {
            var def = new TsLanguageDef (name, lang);
            foreach (var e in exts) by_ext.insert (e, def);
        }

        public TsLanguageDef? lookup_for_file (File file) {
            var basename = file.get_basename ();
            if (basename == null) return null;
            var dot = basename.last_index_of_char ('.');
            if (dot < 0) return null;
            var ext = basename.substring (dot + 1).down ();
            return by_ext.lookup (ext);
        }

        public void ensure_queries_loaded (TsLanguageDef def) {
            if (def.queries_loaded) return;
            def.queries_loaded = true;

            // Search order: user data dir, system data dirs, dev source tree fallback.
            string[] roots = {};
            roots += Path.build_filename (Environment.get_user_data_dir (),
                                          "singularity-edit", "queries");
            foreach (var d in Environment.get_system_data_dirs ()) {
                roots += Path.build_filename (d, "singularity-edit", "queries");
            }
            // Dev fallback: ../share next to bundled installs
            roots += "/usr/share/singularity-edit/queries";
            roots += "/usr/local/share/singularity-edit/queries";

            foreach (var root in roots) {
                var hp = Path.build_filename (root, def.name, "highlights.scm");
                if (!FileUtils.test (hp, FileTest.EXISTS)) continue;

                def.highlights_query = load_query (def.language, hp);
                var fp = Path.build_filename (root, def.name, "folds.scm");
                if (FileUtils.test (fp, FileTest.EXISTS))
                    def.folds_query = load_query (def.language, fp);
                var lp = Path.build_filename (root, def.name, "locals.scm");
                if (FileUtils.test (lp, FileTest.EXISTS))
                    def.locals_query = load_query (def.language, lp);
                return;
            }
            warning ("tree-sitter: no queries found for %s", def.name);
        }

        private TS.Query? load_query (TS.Language lang, string path) {
            string contents;
            try {
                FileUtils.get_contents (path, out contents);
            } catch (Error e) {
                warning ("ts: read %s failed: %s", path, e.message);
                return null;
            }
            uint32 err_off = 0;
            TS.QueryError err_type = TS.QueryError.None;
            var q = new TS.Query (lang, (uint8[]) contents.data,
                                  (uint32) contents.length, out err_off, out err_type);
            if (err_type != TS.QueryError.None) {
                warning ("ts: query %s rejected at byte %u (error code %d)",
                         path, err_off, (int) err_type);
                return null;
            }
            return q;
        }
    }
}
