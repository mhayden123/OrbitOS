package dev.orbitos.display;

import dan200.computercraft.shared.computer.core.ServerComputer;
import dan200.computercraft.shared.computer.core.ServerContext;
import dan200.computercraft.shared.computer.terminal.NetworkedTerminal;
import dan200.computercraft.shared.pocket.core.PocketServerComputer;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.LinkedHashMap;
import java.util.Map;
import org.slf4j.LoggerFactory;

public final class DisplayState {
    private final ServerComputer computer;
    private final NetworkedTerminal terminal;
    private final int defaultWidth, defaultHeight;
    private PreviewController preview;
    private Path path;

    public DisplayState(ServerComputer computer, NetworkedTerminal terminal) {
        this.computer = computer; this.terminal = terminal;
        defaultWidth = terminal.getWidth(); defaultHeight = terminal.getHeight();
    }
    private void resize(PreviewController.Size size) {
        terminal.resize(size.width(), size.height());
        computer.queueEvent("term_resize");
        computer.queueEvent("orbit_display_changed");
    }
    private void save(PreviewController.Size size) throws IOException {
        Files.createDirectories(path.getParent());
        Path staging = path.resolveSibling(path.getFileName() + ".tmp");
        Files.writeString(staging, size.width() + " " + size.height() + "\n", StandardCharsets.UTF_8);
        try { Files.move(staging, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE); }
        catch (AtomicMoveNotSupportedException ignored) { Files.move(staging, path, StandardCopyOption.REPLACE_EXISTING); }
    }
    private void initialize() {
        if (preview != null) return;
        path = ServerContext.get(computer.getLevel().getServer()).storageDir()
            .resolve("orbit-display").resolve(computer.getID() + ".txt");
        var size = new PreviewController.Size(
            Math.clamp(defaultWidth, PreviewController.MIN_WIDTH, PreviewController.MAX_WIDTH),
            Math.clamp(defaultHeight, PreviewController.MIN_HEIGHT, PreviewController.MAX_HEIGHT));
        if (Files.isRegularFile(path)) {
            try {
                if (Files.size(path) > 64) throw new IOException("Oversized display settings");
                String[] parts = Files.readString(path).trim().split("\\s+");
                if (parts.length != 2) throw new IOException("Invalid display settings");
                size = new PreviewController.Size(Integer.parseInt(parts[0]), Integer.parseInt(parts[1]));
            } catch (IOException | IllegalArgumentException error) {
                LoggerFactory.getLogger("orbit_display").warn("Ignoring invalid display settings for computer {}", computer.getID(), error);
            }
        }
        preview = new PreviewController(new PreviewController.Target() {
            public void resize(PreviewController.Size value) { DisplayState.this.resize(value); }
            public void save(PreviewController.Size value) throws IOException { DisplayState.this.save(value); }
        }, System::nanoTime, size);
        if (terminal.getWidth() != size.width() || terminal.getHeight() != size.height()) resize(size);
    }
    public void tick() { initialize(); preview.tick(computer.isOn()); }
    public String preview(int width, int height) { initialize(); return preview.preview(new PreviewController.Size(width, height)); }
    public void keep(String token) throws IOException { initialize(); preview.keep(token); }
    public void revert(String token) { initialize(); preview.revert(token); }
    public Map<String, Object> info() {
        initialize(); preview.tick(computer.isOn());
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("apiVersion", 1); info.put("version", "0.1.0");
        info.put("kind", computer instanceof PocketServerComputer ? "pocket" : "computer");
        info.put("width", terminal.getWidth()); info.put("height", terminal.getHeight());
        info.put("defaultWidth", Math.clamp(defaultWidth, PreviewController.MIN_WIDTH, PreviewController.MAX_WIDTH));
        info.put("defaultHeight", Math.clamp(defaultHeight, PreviewController.MIN_HEIGHT, PreviewController.MAX_HEIGHT));
        info.put("minWidth", PreviewController.MIN_WIDTH); info.put("maxWidth", PreviewController.MAX_WIDTH);
        info.put("minHeight", PreviewController.MIN_HEIGHT); info.put("maxHeight", PreviewController.MAX_HEIGHT);
        info.put("previewSeconds", PreviewController.PREVIEW_SECONDS);
        info.put("remaining", preview.remaining());
        if (preview.token() != null) info.put("preview", preview.token());
        return info;
    }
}
