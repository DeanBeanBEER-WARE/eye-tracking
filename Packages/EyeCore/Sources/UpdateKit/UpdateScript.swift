/// The detached shell script that swaps the app bundle after the app has quit.
///
/// It waits up to 60 s for the app process to exit, moves the installed bundle aside, copies the new one into place
/// (restoring the old bundle if the copy fails), removes the work directory and launches the target.
public enum UpdateScript {
    /// The shell that runs the script.
    public static let shell = "/bin/sh"

    /// The process name of the script (`$0`).
    public static let processName = "eye-tracking-update"

    /// The script text; arguments are the pid, the new app, the target and the work directory.
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

    /// Builds the arguments of the shell.
    ///
    /// - Parameters:
    ///   - pid: The process identifier of the running app.
    ///   - staged: The path of the new app bundle.
    ///   - target: The path of the installed app bundle.
    ///   - workDirectory: The temporary directory the script removes when done.
    /// - Returns: The arguments after the shell path.
    public static func arguments(pid: Int32, staged: String, target: String, workDirectory: String) -> [String] {
        ["-c", text, processName, String(pid), staged, target, workDirectory]
    }
}
