module progresso.util;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.conv;
import std.exception;
import std.format;
import std.range;
import std.string;
import std.uni;

package size_t terminalWidth(const dchar c) @safe pure {
	return widthTable[c];
}
///
@safe pure unittest {
	assert('a'.terminalWidth == 1);
	assert('🧀'.terminalWidth == 2);
	assert('／'.terminalWidth == 2);
}

package size_t terminalWidth(const char[] str) @safe pure {
	// we assume that combining marks don't contribute to character width. this may or may not be accurate
	return str.byGrapheme.map!(x => x[0].terminalWidth).sum;
}
///
@safe pure unittest {
	assert("abc".terminalWidth == 3);
	assert("🧀".terminalWidth == 2);
	assert("🐈‍⬛".terminalWidth == 2);
}

package auto abbreviated(const char[] str, size_t maxLength) {
	static struct Result {
		const(char)[] str;
		size_t maxLength;
		private void __forceCompileCheck() const {
			toString(nullSink);
		}
		void toString(S)(S sink) const {
			enum abbrevString = "...";
			if (str.terminalWidth > maxLength) {
				if (maxLength >= abbrevString.length) {
					long charsLeft = maxLength - abbrevString.length;
					auto codePoints = str.byGrapheme.byCodePoint;
					while (!codePoints.empty && (codePoints.front.terminalWidth <= charsLeft)) {
						put(sink, codePoints.front);
						charsLeft -= codePoints.front.terminalWidth;
						codePoints.popFront();
					}
				}
				put(sink, abbrevString[0 .. min(abbrevString.length, maxLength)]);
			} else {
				put(sink, str);
			}
		}
	}
	return Result(str, maxLength);
}
///
@safe pure unittest {
	assert("abc".abbreviated(4).text == "abc");
	assert("abc".abbreviated(3).text == "abc");
	assert("abc".abbreviated(0).text == "");
	assert("🧀🧀🧀".abbreviated(3).text == "...");
	assert("🧀🧀🧀🧀🧀".abbreviated(5).text == "🧀...");
	assert("🧀🐈‍🧀🧀🧀".abbreviated(7).text == "🧀🐈...");
}

package struct PrettyBytesPrinter {
	ulong amount;
	private static immutable unitPrefixes = ["K", "M", "G", "T", "P", "E", "Z", "Y", "R", "Q"];
	void toString(S)(auto ref S sink) const {
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

immutable widthTable = () {
	ubyte[0x110000] width = 1;
	foreach (line; import("EastAsianWidth.txt").lineSplitter) {
		if (line.startsWith("#") || (line == "")) {
			continue;
		}
		uint rangeEnd;
		const hexSpec = singleSpec("%X");
		uint rangeStart = unformatValue!uint(line, hexSpec);
		if (line.startsWith("..")) {
			line = line[2 .. $];
			rangeEnd = unformatValue!uint(line, hexSpec);
		} else {
			rangeEnd = rangeStart;
		}
		auto eawPropSplit = line.findSplit("; ")[2].findSplit(" #")[0].strip;
		if (eawPropSplit.among("W", "F")) {
			width[rangeStart .. rangeEnd + 1] = 2;
		}
	}
	return width;
} ();
