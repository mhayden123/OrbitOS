package dev.orbitos.display;

import java.io.IOException;
import java.util.concurrent.atomic.AtomicLong;

public final class DisplayTests {
    private static final class Target implements PreviewController.Target {
        PreviewController.Size visible, saved;
        boolean fail;
        public void resize(PreviewController.Size value) { visible = value; }
        public void save(PreviewController.Size value) throws IOException {
            if (fail) throw new IOException("Disk full");
            saved = value;
        }
    }
    public static void main(String[] args) throws Exception {
        var time = new AtomicLong(); var target = new Target();
        var original = new PreviewController.Size(51, 19);
        var large = new PreviewController.Size(80, 30);
        var controller = new PreviewController(target, time::get, original);
        String token = controller.preview(large);
        assert target.visible.equals(large) && controller.remaining() == 15 && target.saved == null;
        try { controller.keep("wrong token"); throw new AssertionError(); } catch (IllegalStateException expected) { }
        try { controller.preview(original); throw new AssertionError(); } catch (IllegalStateException expected) { }
        time.set(15_000_000_000L); controller.tick(true);
        assert target.visible.equals(original) && controller.token() == null;
        try { controller.keep(token); throw new AssertionError(); } catch (IllegalStateException expected) { }
        token = controller.preview(large); controller.keep(token);
        assert target.saved.equals(large);
        time.set(40_000_000_000L); controller.tick(true); assert controller.current().equals(large);
        token = controller.preview(original); controller.revert(token); assert controller.current().equals(large);
        controller.preview(original); controller.tick(false); assert controller.current().equals(large);
        token = controller.preview(original); target.fail = true;
        try { controller.keep(token); throw new AssertionError(); } catch (IOException expected) { }
        assert controller.token() != null;
        time.set(60_000_000_000L); controller.tick(true); assert controller.current().equals(large);
        for (int[] size : new int[][]{{25,20},{80,12},{161,30},{80,61},{0,0}}) {
            try { new PreviewController.Size(size[0],size[1]); throw new AssertionError(); } catch (IllegalArgumentException expected) { }
        }
        for (int[] screen : new int[][]{{426,267},{640,400},{1920,1080},{320,200}}) {
            for (int[] content : new int[][]{{353,199},{527,298},{1007,568},{257,298}}) {
                var fit = Viewport.fit(screen[0],screen[1],content[0],content[1]);
                assert content[0]*fit.scale() <= screen[0] && content[1]*fit.scale() <= screen[1];
                double cell = 183.25;
                assert Math.abs(fit.logical(cell * fit.scale()) - cell) < 0.001;
            }
        }
        System.out.println("Display tests passed: timed rollback, keep, revert, shutdown, stale tokens, disk failure, bounds and input transforms.");
    }
}
