package dev.orbitos.display;

import dan200.computercraft.api.lua.ILuaAPI;
import dan200.computercraft.api.lua.LuaException;
import dan200.computercraft.api.lua.LuaFunction;
import java.io.IOException;
import java.util.Map;

public final class ResolutionAPI implements ILuaAPI {
    private final DisplayState display;
    public ResolutionAPI(DisplayState display) { this.display = display; }
    public String[] getNames() { return new String[]{"orbit_display"}; }
    @LuaFunction(mainThread = true)
    public Map<String, Object> getInfo() { return display.info(); }
    @LuaFunction(mainThread = true)
    public String preview(int width, int height) throws LuaException {
        try { return display.preview(width, height); }
        catch (IllegalArgumentException | IllegalStateException error) { throw new LuaException(error.getMessage()); }
    }
    @LuaFunction(mainThread = true)
    public boolean keep(String token) throws LuaException {
        try { display.keep(token); return true; }
        catch (IOException error) { throw new LuaException("Could not save this resolution. The preview will revert."); }
        catch (IllegalStateException error) { throw new LuaException(error.getMessage()); }
    }
    @LuaFunction(mainThread = true)
    public boolean revert(String token) throws LuaException {
        try { display.revert(token); return true; }
        catch (IllegalStateException error) { throw new LuaException(error.getMessage()); }
    }
}
