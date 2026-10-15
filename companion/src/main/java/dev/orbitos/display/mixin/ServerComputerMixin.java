package dev.orbitos.display.mixin;

import dan200.computercraft.shared.computer.core.ServerComputer;
import dan200.computercraft.shared.computer.terminal.NetworkedTerminal;
import dev.orbitos.display.DisplayHost;
import dev.orbitos.display.DisplayState;
import org.spongepowered.asm.mixin.*;
import org.spongepowered.asm.mixin.injection.*;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(value = ServerComputer.class, remap = false)
public abstract class ServerComputerMixin implements DisplayHost {
    @Shadow @Final private NetworkedTerminal terminal;
    @Unique private DisplayState orbit$display;
    public DisplayState orbit$getDisplay() {
        if (orbit$display == null) orbit$display = new DisplayState((ServerComputer) (Object) this, terminal);
        return orbit$display;
    }
    @Inject(method = "tickServer", at = @At("HEAD"))
    private void orbit$tick(CallbackInfo callback) {
        if (orbit$display != null) orbit$display.tick();
    }
}
