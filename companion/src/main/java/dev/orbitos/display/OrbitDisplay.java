package dev.orbitos.display;

import dan200.computercraft.api.ComputerCraftAPI;
import dan200.computercraft.api.component.ComputerComponents;
import dev.orbitos.display.mixin.ComputerSystemAccessor;
import net.fabricmc.api.ModInitializer;

public final class OrbitDisplay implements ModInitializer {
    public void onInitialize() {
        ComputerCraftAPI.registerAPIFactory(system -> {
            // Turtle inventory screens have a different layout; keep their native 39x13 terminal.
            if (system.getComponent(ComputerComponents.TURTLE) != null) return null;
            var computer = ((ComputerSystemAccessor) system).orbit$getComputer();
            return new ResolutionAPI(((DisplayHost) computer).orbit$getDisplay());
        });
    }
}
