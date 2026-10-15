package dev.orbitos.display;

import java.io.IOException;
import java.util.UUID;
import java.util.function.LongSupplier;

/** Server-owned preview lifecycle. It does not depend on the Lua program staying alive. */
public final class PreviewController {
    public static final int MIN_WIDTH = 26, MIN_HEIGHT = 13, MAX_WIDTH = 160, MAX_HEIGHT = 60;
    public static final int PREVIEW_SECONDS = 15;
    public record Size(int width, int height) {
        public Size {
            if (width < MIN_WIDTH || width > MAX_WIDTH || height < MIN_HEIGHT || height > MAX_HEIGHT)
                throw new IllegalArgumentException("Use 26-160 columns and 13-60 rows.");
        }
    }
    public interface Target {
        void resize(Size size);
        void save(Size size) throws IOException;
    }
    private final Target target;
    private final LongSupplier clock;
    private Size current, previous;
    private String token;
    private long deadline;

    public PreviewController(Target target, LongSupplier clock, Size initial) {
        this.target = target; this.clock = clock; this.current = initial;
    }
    public Size current() { return current; }
    public String token() { return token; }
    public int remaining() {
        return token == null ? 0 : (int) Math.max(0, (deadline - clock.getAsLong() + 999_999_999L) / 1_000_000_000L);
    }
    public String preview(Size size) {
        tick(true);
        if (token != null) throw new IllegalStateException("Confirm or revert the current preview first.");
        previous = current;
        target.resize(size);
        current = size;
        token = UUID.randomUUID().toString();
        deadline = clock.getAsLong() + PREVIEW_SECONDS * 1_000_000_000L;
        return token;
    }
    public void keep(String value) throws IOException {
        check(value);
        // A failed write keeps the preview timer active, so it still rolls back.
        target.save(current);
        token = null; previous = null;
    }
    public void revert(String value) { check(value); rollback(); }
    private void check(String value) {
        tick(true);
        if (token == null || !token.equals(value)) throw new IllegalStateException("This preview has expired or was already closed.");
    }
    private void rollback() {
        target.resize(previous);
        current = previous; previous = null; token = null;
    }
    public void tick(boolean computerOn) {
        if (token != null && (!computerOn || clock.getAsLong() >= deadline)) rollback();
    }
}
