import Foundation

/// Delivers a channel-close callback at most once.
///
/// SSH child channels commonly see `errorCaught` followed by `channelInactive`
/// (because the error path closes the channel). Without this, the session
/// reports `.failed` and then `.closed`, dropping the error.
struct ChannelCloseOnce {
    private var fired = false

    /// Forward `error` to `handler` the first time only. Later calls are ignored,
    /// so a subsequent clean inactive does not wipe a previous error.
    mutating func deliver(_ error: Error?, to handler: (Error?) -> Void) {
        guard !fired else { return }
        fired = true
        handler(error)
    }
}
