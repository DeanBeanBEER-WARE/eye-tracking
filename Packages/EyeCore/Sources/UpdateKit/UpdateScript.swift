public enum UpdateScript {
    public static let shell = "/bin/sh"

    public static let processName = "eye-tracking-update"

    public static let text = """
        pid="$1"; new="$2"; target="$3"; workdir="$4"
        backup="$target.old"
        i=0
        while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 120 ]; do
            sleep 0.5
            i=$((i + 1))
        done
        rm -rf "$backup"
        if mv "$target" "$backup"; then
            if /usr/bin/ditto "$new" "$target"; then
                rm -rf "$backup"
                echo "eye-tracking update: installed $target"
            else
                echo "eye-tracking update: copy failed, restoring previous version"
                rm -rf "$target"
                mv "$backup" "$target"
            fi
        else
            echo "eye-tracking update: could not move $target"
        fi
        rm -rf "$workdir"
        /usr/bin/open "$target"
        """

    public static func arguments(pid: Int32, staged: String, target: String, workDirectory: String) -> [String] {
        ["-c", text, processName, String(pid), staged, target, workDirectory]
    }
}
