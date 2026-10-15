package dev.orbitos.display.client;

import dan200.computercraft.client.gui.AbstractComputerScreen;
import dan200.computercraft.client.gui.GuiSprites;
import dan200.computercraft.client.gui.widgets.TerminalWidget;
import dan200.computercraft.shared.computer.inventory.AbstractComputerMenu;
import dev.orbitos.display.Viewport;
import net.minecraft.client.gui.GuiGraphicsExtractor;
import net.minecraft.client.input.MouseButtonEvent;
import net.minecraft.client.renderer.RenderPipelines;
import net.minecraft.network.chat.Component;
import net.minecraft.world.entity.player.Inventory;

/** Rebuilds the terminal widget after a resize and fits the whole computer GUI into the viewport. */
public final class OrbitComputerScreen<T extends AbstractComputerMenu> extends AbstractComputerScreen<T> {
    private static final int BORDER = 12, SIDEBAR = 17;
    private Viewport viewport;
    private int availableWidth, availableHeight, columns, rows;
    public int viewportWidth() { return availableWidth; }
    public int viewportHeight() { return availableHeight; }
    public OrbitComputerScreen(T menu, Inventory inventory, Component title) {
        super(menu, inventory, title, BORDER, TerminalWidget.getWidth(menu.getTerminal().getWidth()) + 2 * BORDER + SIDEBAR,
            TerminalWidget.getHeight(menu.getTerminal().getHeight()) + 2 * BORDER);
    }
    private int contentWidth() { return TerminalWidget.getWidth(terminalData.getWidth()) + 2 * BORDER + SIDEBAR; }
    private int contentHeight() { return TerminalWidget.getHeight(terminalData.getHeight()) + 2 * BORDER; }
    @Override protected void init() {
        availableWidth = width; availableHeight = height;
        viewport = Viewport.fit(width, height, contentWidth(), contentHeight());
        width = viewport.width(); height = viewport.height();
        columns = terminalData.getWidth(); rows = terminalData.getHeight();
        super.init();
    }
    @Override protected TerminalWidget createTerminal() {
        leftPos = (width - contentWidth()) / 2; topPos = (height - contentHeight()) / 2;
        return new TerminalWidget(terminalData, computerInput, computerActions, leftPos + SIDEBAR + BORDER, topPos + BORDER);
    }
    private void checkTerminalSize() {
        if (columns != terminalData.getWidth() || rows != terminalData.getHeight()) {
            width = availableWidth; height = availableHeight;
            rebuildWidgets();
        }
    }
    @Override public void containerTick() {
        checkTerminalSize(); super.containerTick();
    }
    @Override public void extractBackground(GuiGraphicsExtractor graphics, int mouseX, int mouseY, float delta) {
        checkTerminalSize();
        // The world/menu backdrop stays at normal GUI scale.
        int logicalWidth = width, logicalHeight = height;
        width = availableWidth; height = availableHeight;
        super.extractBackground(graphics, mouseX, mouseY, delta);
        width = logicalWidth; height = logicalHeight;
        graphics.pose().pushMatrix();
        graphics.pose().scale(viewport.scale(), viewport.scale());
        var widget = getTerminal();
        var textures = GuiSprites.getComputerTextures(family);
        graphics.blitSprite(RenderPipelines.GUI_TEXTURED, textures.border(), widget.getX() - BORDER, widget.getY() - BORDER,
            widget.getWidth() + 2 * BORDER, widget.getHeight() + 2 * BORDER);
        graphics.blitSprite(RenderPipelines.GUI_TEXTURED, textures.sidebar(), leftPos, topPos + BORDER, SIDEBAR, 38);
        graphics.pose().popMatrix();
    }
    @Override public void extractRenderState(GuiGraphicsExtractor graphics, int mouseX, int mouseY, float delta) {
        graphics.pose().pushMatrix();
        graphics.pose().scale(viewport.scale(), viewport.scale());
        super.extractRenderState(graphics, (int) viewport.logical(mouseX), (int) viewport.logical(mouseY), delta);
        graphics.pose().popMatrix();
    }
    private MouseButtonEvent logical(MouseButtonEvent event) {
        return new MouseButtonEvent(viewport.logical(event.x()), viewport.logical(event.y()), event.buttonInfo());
    }
    @Override public boolean mouseClicked(MouseButtonEvent event, boolean doubleClick) { return super.mouseClicked(logical(event), doubleClick); }
    @Override public boolean mouseReleased(MouseButtonEvent event) { return super.mouseReleased(logical(event)); }
    @Override public boolean mouseDragged(MouseButtonEvent event, double dx, double dy) {
        return super.mouseDragged(logical(event), viewport.logical(dx), viewport.logical(dy));
    }
    @Override public boolean mouseScrolled(double x, double y, double dx, double dy) {
        return super.mouseScrolled(viewport.logical(x), viewport.logical(y), dx, dy);
    }
    @Override public void mouseMoved(double x, double y) { super.mouseMoved(viewport.logical(x), viewport.logical(y)); }
}
