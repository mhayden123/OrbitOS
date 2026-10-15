package dev.orbitos.display.client;

import java.util.List;
import mezz.jei.api.IModPlugin;
import mezz.jei.api.gui.handlers.IGuiContainerHandler;
import mezz.jei.api.gui.handlers.IGuiProperties;
import mezz.jei.api.registration.IGuiHandlerRegistration;
import net.minecraft.client.gui.screens.Screen;
import net.minecraft.client.renderer.Rect2i;
import net.minecraft.resources.Identifier;

/** Optional JEI entrypoint. The computer has no inventory and owns its whole viewport. */
public final class OrbitJeiPlugin implements IModPlugin {
    public Identifier getPluginUid() { return Identifier.fromNamespaceAndPath("orbit_display", "screens"); }
    private record Properties(Class<? extends Screen> screenClass, int guiLeft, int guiTop,
        int guiXSize, int guiYSize, int screenWidth, int screenHeight) implements IGuiProperties { }
    @SuppressWarnings("rawtypes")
    public void registerGuiHandlers(IGuiHandlerRegistration registration) {
        registration.addGuiScreenHandler(OrbitComputerScreen.class, screen -> new Properties(
            OrbitComputerScreen.class, 0, 0, screen.viewportWidth(), screen.viewportHeight(),
            screen.viewportWidth(), screen.viewportHeight()));
        registration.addGenericGuiContainerHandler(OrbitComputerScreen.class, new IGuiContainerHandler<OrbitComputerScreen<?>>() {
            public List<Rect2i> getGuiExtraAreas(OrbitComputerScreen<?> screen) {
                return List.of(new Rect2i(0, 0, screen.width, screen.height));
            }
        });
    }
}
