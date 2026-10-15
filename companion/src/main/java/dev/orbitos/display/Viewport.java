package dev.orbitos.display;

/** Shared drawing and input transform, independent of Minecraft for round-trip testing. */
public record Viewport(float scale, int width, int height) {
    public static Viewport fit(int availableWidth, int availableHeight, int contentWidth, int contentHeight) {
        float scale = Math.min(1f, Math.min(Math.max(1, availableWidth - 8f) / contentWidth,
            Math.max(1, availableHeight - 8f) / contentHeight));
        return new Viewport(scale, (int) (availableWidth / scale), (int) (availableHeight / scale));
    }
    public double logical(double coordinate) { return coordinate / scale; }
}
