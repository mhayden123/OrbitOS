package dev.orbitos.display.mixin;

import dan200.computercraft.shared.computer.core.ServerComputer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(targets = "dan200.computercraft.shared.computer.core.ComputerSystem", remap = false)
public interface ComputerSystemAccessor {
    @Accessor("computer") ServerComputer orbit$getComputer();
}
