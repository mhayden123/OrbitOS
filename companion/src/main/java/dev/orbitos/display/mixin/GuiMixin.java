package dev.orbitos.display.mixin;

import dan200.computercraft.client.gui.ComputerScreen;
import dev.orbitos.display.client.OrbitComputerScreen;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.Gui;
import net.minecraft.client.gui.screens.Screen;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.ModifyVariable;

@Mixin(value = Gui.class, remap = false)
public abstract class GuiMixin {
    @ModifyVariable(method = "setScreen", at = @At("HEAD"), argsOnly = true)
    private Screen orbit$fitComputer(Screen screen) {
        var player = Minecraft.getInstance().player;
        if (screen instanceof ComputerScreen<?> computer && player != null)
            return new OrbitComputerScreen<>(computer.getMenu(), player.getInventory(), computer.getTitle());
        return screen;
    }
}
