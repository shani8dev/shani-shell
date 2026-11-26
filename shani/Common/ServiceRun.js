.pragma library
// The shared start of a service command: name it, mark it busy, clear the last
// error. Each service keeps its own error words in its finished() handler.
function begin(self, what) {
    self.what = what;
    self.busy = true;
    self.error = "";
    return true;
}
