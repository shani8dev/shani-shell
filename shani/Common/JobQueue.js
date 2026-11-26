.pragma library
// Run the next queued bridge command when the current one has finished. The
// service owns the queue, the busy flag and start(); this only orders them.
function pump(self, job) {
    if (self.busy || job.running || !self.pending.length) return;
    const next = self.pending[0];
    self.pending = self.pending.slice(1);
    self.start(next.what, next.args);
}
