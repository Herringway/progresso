module progresso.util;

import std.conv;
import std.exception;
import std.range;

package struct PrettyBytesPrinter {
	ulong amount;
	private static immutable unitPrefixes = ["K", "M", "G", "T", "P", "E", "Z", "Y", "R", "Q"];
	void toString(S)(auto ref S sink) const {
		import std.format : formattedWrite;
		double tmp = amount;
		uint prefix = 0;
		while (tmp >= 1024) {
			tmp /= 1024;
			prefix++;
		}
		sink.formattedWrite!"%.0f"(tmp);
		if (prefix > 0) {
			put(sink, unitPrefixes[prefix - 1]);
			put(sink, "i");
		}
		put(sink, "B");
	}
}
@safe pure unittest {
	assert(PrettyBytesPrinter(1023).text == "1023B");
	assert(PrettyBytesPrinter(1024).text == "1KiB");
}

package auto getConsoleDimensions() @trusted {
	static struct Result {
		uint width;
		uint height;
	}

	version(Windows) {
		import core.sys.windows.winbase;
		import core.sys.windows.wincon;
		auto handle = GetStdHandle(STD_OUTPUT_HANDLE);
		CONSOLE_SCREEN_BUFFER_INFO info;
		enforce(GetConsoleScreenBufferInfo(handle, &info), "Invalid console?");
		return Result(info.dwSize.X, info.dwSize.Y);
	} else version(Posix) {
		import core.sys.posix.sys.ioctl : ioctl, TIOCGWINSZ, winsize;
		import std.stdio : File;
		winsize ws;
		auto file = File("/dev/tty", "r");
		enforce(ioctl(file.fileno, TIOCGWINSZ, &ws) >= 0, "Failed getting terminal dimensions");

		return Result(ws.ws_col, ws.ws_row);
	}
}

package bool isValidConsole() @trusted {
	version(Windows) {
		import core.sys.windows.winbase;
		import core.sys.windows.wincon;
		auto handle = GetStdHandle(STD_OUTPUT_HANDLE);
		CONSOLE_SCREEN_BUFFER_INFO _;
		return !!GetConsoleScreenBufferInfo(handle, &_);
	} else version(Posix) {
		import std.stdio : stdout;
		import core.sys.posix.unistd : isatty;
		return !!isatty(stdout.fileno);
	}
}
