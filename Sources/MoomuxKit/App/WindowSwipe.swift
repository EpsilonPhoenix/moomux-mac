/// A sideways swipe on an attached pane steps through the session's tmux
/// windows: fingers left is the next window, fingers right the previous, the
/// way a swipe pages anything else on either device. The core switches it
/// (`AppState.selectWindow`), not a typed prefix, so a remapped one is fine.
public enum WindowSwipe {
    /// +1 for the next window, -1 for the previous, nil when the gesture is
    /// not sideways enough and far enough to be a swipe rather than the drift
    /// of a vertical scroll. `dx` is the fingers' travel, positive to the
    /// right; `dy` is vertical travel, summed unsigned by the caller.
    public static func step(dx: Double, dy: Double, minimum: Double) -> Int? {
        guard abs(dx) >= minimum, abs(dx) > 2 * abs(dy) else { return nil }
        return dx < 0 ? 1 : -1
    }

    public static func demo() {
        assert(step(dx: -80, dy: 5, minimum: 60) == 1, "fingers left is next")
        assert(step(dx: 80, dy: -5, minimum: 60) == -1, "fingers right is previous")
        assert(step(dx: -40, dy: 0, minimum: 60) == nil, "too short")
        assert(step(dx: -80, dy: 50, minimum: 60) == nil, "a diagonal scroll is not a swipe")
    }
}
