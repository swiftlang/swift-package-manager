package swift.example;
import org.libsdl.app.SDLActivity;

public class ExampleActivity extends SDLActivity {
    @Override
    protected String[] getLibraries() {
        return new String[]{ "AndroidExample" };
    }
}