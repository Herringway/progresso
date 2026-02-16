module progresso.progresstracker;

public import pixelmancy : RGB = RGB888;
import progresso.bars;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.conv;
import std.datetime;
import std.exception;
import std.range;
import std.stdio;
import std.string;
import std.typecons;

enum ProgressUnit {
	none,
	bytes
}

enum ProgressItemState {
	inactive,
	active,
	failed,
	complete,
}

struct ProgressItem {
	ProgressItem[] subItems;
	ProgressItemState state;
	ulong id;
	string name;
	string status;
	ulong width = 10;
	ulong maximum;
	ulong current;
	bool showPercentage;
	ProgressUnit unit;
	ColourMode colourMode;
	RGB from;
	RGB to;
	private ubyte donePrinting;
	private bool isRoot;
	ulong amount() const @safe pure {
		if (state == ProgressItemState.complete) {
			return total;
		}
		if (subItems != []) {
			return subItems.filter!(x => x.state == ProgressItemState.complete).walkLength;
		}
		return current;
	}
	ulong total() const @safe pure {
		if (subItems != []) {
			return subItems.length;
		}
		return maximum;
	}
}

ref inout(ProgressItem) matching(return inout ProgressItem[] items, ulong id) @safe pure {
	foreach (ref item; items) {
		if (item.id == id) {
			return item;
		}
	}
	throw new Exception("No match for "~id.text);
}

struct ProgressTracker {
	private static struct Options {
		bool showTotal;
		bool hideItemProgress;
		bool hideTotalProgress;
		bool totalItemsOnly;
		Nullable!Duration minimumUpdateWait;
	}
	private Options options;
	private ProgressItem root = { name: "Total", isRoot: true };
	private Nullable!MonoTime nextUpdate;
	private size_t lastLinesPrinted;
	ref auto showTotal() => options.showTotal;
	ref auto hideItemProgress() => options.hideItemProgress;
	ref auto hideTotalProgress() => options.hideTotalProgress;
	ref auto totalItemsOnly() => options.totalItemsOnly;
	ref auto minimumUpdateWait() => options.minimumUpdateWait;
	ref ProgressItem addNewItem(ProgressItem newItem) @safe pure {
		root.subItems ~= newItem;
		return root.subItems[$ - 1];
	}
	auto ref matching(ulong id) @safe pure {
		return root.subItems.matching(id);
	}
	void updateDisplay(bool force = false) @safe {
		if (!isValidConsole()) {
			return;
		}
		if (!force && !minimumUpdateWait.isNull) {
			auto now = MonoTime.currTime();
			if (nextUpdate.get(now) > now) {
				return;
			}
			nextUpdate = now + minimumUpdateWait.get();
		}
		updateBarState();
		if (lastLinesPrinted > 0) { // rewind to start of "active" printing area
			foreach (_; 0 .. lastLinesPrinted) {
				write("\x1B[1F\x1B[K");
			}
		}
		const dimensions = getConsoleDimensions();
		writeln(printer(lastLinesPrinted, dimensions.width));
	}
	auto printer(Bar = UnicodeProgressBar2)() const {
		size_t _;
		return printer!Bar(_, ulong.max);
	}
	auto printer(Bar = UnicodeProgressBar2)(out size_t lines, ulong maxWidth) const {
		struct Printer {
			private const ProgressItem total;
			const Options options;
			void toString(S)(auto ref S sink) const {
				import std.format : formattedWrite;
				import std.range : put, repeat;
				import std.uni : byGrapheme;
				bool shouldPrintNewline;
				void printBar(const ProgressItem item, bool hideProgress, int depth, bool linesCount) {
					size_t charCount;
					struct CharCounter {
						void put(const(char)[] text) {
							static import std.range;
							charCount += text.byGrapheme.walkLength;
							std.range.put(sink, text);
						}
					}
					void printActualBar() {
						CharCounter charCounter;
						Bar bar;
						bar.current = item.amount;
						bar.maximum = item.total;
						bar.width = item.width;
						bar.colourMode = item.colourMode;
						bar.from = item.from;
						bar.to = item.to;
						bar.showPercentage = item.showPercentage;
						bar.complete = item.state == ProgressItemState.complete;

						if (linesCount) {
							lines++;
						}
						if (shouldPrintNewline) {
							put(sink, "\n");
						}
						shouldPrintNewline = true;
						enum indentation = "    ";
						if (depth >= 1) {
							charCounter.formattedWrite!"%-(%s%)"(indentation.repeat(depth));
						}
						charCounter.formattedWrite!"%s"(bar);
						put(charCounter, " ");
						if (!hideProgress) {
							final switch (item.unit) {
								case ProgressUnit.none:
									charCounter.formattedWrite!"%s/%s ("(bar.current, bar.maximum);
									break;
								case ProgressUnit.bytes:
									charCounter.formattedWrite!"%s/%s ("(PrettyBytesPrinter(bar.current), PrettyBytesPrinter(bar.maximum));
									break;
							}
						}
						charCounter.formattedWrite!"%s"(bar.percentage);
						if (!hideProgress) {
							put(charCounter, ")");
						}
						const maxLabelLength = maxWidth - charCount - item.status.length - 6;
						if (item.name.length > maxLabelLength) {
							sink.formattedWrite!" - %s..."(item.name[0 .. maxLabelLength]);
						} else {
							sink.formattedWrite!" - %s"(item.name);
						}
						if (item.status != "") {
							sink.formattedWrite!" (%s)"(item.status);
						}
					}
					if (!item.isRoot) {
						printActualBar();
					}
					foreach (subItem; item.subItems) {
						if ((subItem.donePrinting == 2) && subItem.subItems.length) {
							continue;
						}
						if (subItem.state == ProgressItemState.complete) {
							printBar(subItem, hideProgress, depth + 1, !subItem.donePrinting && !item.donePrinting);
						}
					}
					foreach (subItem; item.subItems) {
						if (subItem.state == ProgressItemState.active) {
							printBar(subItem, hideProgress, depth + 1, !subItem.donePrinting && !item.donePrinting);
						}
					}
					if (item.isRoot && options.showTotal) {
						printActualBar();
					}
				}
				printBar(total, options.hideItemProgress, -1, total.donePrinting != 1);
			}
		}
		return Printer(root, options);
	}
	private void updateBarState() @safe pure {
		void updateItems(ref ProgressItem item) {
			foreach (ref subItem; item.subItems) {
				updateItems(subItem);
				if (item.subItems.length && (item.state == ProgressItemState.complete)) {
					item.current++;
				}
			}
			if (item.donePrinting == 1) {
				item.donePrinting++;
			}
			if ((item.state == ProgressItemState.complete) && !item.donePrinting && item.subItems.length) {
				item.donePrinting++;
			}
			if (item.subItems.length) {
				item.maximum = item.subItems.length;
				if (item.amount == item.total) {
					item.state = ProgressItemState.complete;
					item.status = "Complete";
				}
			}
		}
		updateItems(root);
	}
}

@safe pure unittest {
	static void printerCompiles() {
		import std.range : nullSink;
		ProgressTracker.init.printer().toString(nullSink);
	}
	{
		ProgressTracker tracker;
		tracker.addNewItem(ProgressItem(id: 1, maximum: 1, state: ProgressItemState.active, name: "Test"));
		assert(tracker.printer().text == "[          ] 0/1 (0.00%) - Test");
		tracker.matching(1).state = ProgressItemState.complete;
		assert(tracker.printer().text == "[██████████] 1/1 (100.00%) - Test");
	}
	{
		ProgressTracker tracker;
		tracker.addNewItem(ProgressItem(id: 1, maximum: 1024, state: ProgressItemState.active, unit: ProgressUnit.bytes,  name: "Test"));
		assert(tracker.printer().text == "[          ] 0B/1KiB (0.00%) - Test");
		tracker.matching(1).state = ProgressItemState.complete;
		assert(tracker.printer().text == "[██████████] 1KiB/1KiB (100.00%) - Test");
	}
	{
		ProgressTracker tracker;
		tracker.addNewItem(ProgressItem(id: 1, maximum: 1, state: ProgressItemState.active, name: "Super l01234567890123456789012345678901234567890g"));
		size_t unused;
		assert(tracker.printer(unused, 42).text == "[          ] 0/1 (0.00%) - Super l01234...");
		tracker.matching(1).subItems ~= ProgressItem(id: 1, maximum: 1, state: ProgressItemState.complete, name: "Super l01234567890123456789012345678901234567890g");
		assert(tracker.printer(unused, 42).text == "[██████████] 1/1 (100.00%) - Super l012...\n    [██████████] 1/1 (100.00%) - Super ...");
	}
	{
		ProgressTracker tracker;
		tracker.addNewItem(ProgressItem(id: 1, maximum: 1, state: ProgressItemState.active, name: "Test", subItems: [ProgressItem (id: 1, maximum: 1, name: "Subitem test", state: ProgressItemState.active)]));
		assert(tracker.printer().text == "[          ] 0/1 (0.00%) - Test\n    [          ] 0/1 (0.00%) - Subitem test");
		tracker.matching(1).subItems.matching(1).state = ProgressItemState.complete;
		assert(tracker.printer().text == "[██████████] 1/1 (100.00%) - Test\n    [██████████] 1/1 (100.00%) - Subitem test");
	}
}

struct PrettyBytesPrinter {
	ulong amount;
	private static immutable unitPrefixes = ["K", "M", "G", "T", "P", "E", "Z", "Y", "R", "Q"];
	void toString(S)(auto ref S sink) const {
		import std.format : formattedWrite;
		import std.range : put;
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

private void demo()() {
	import core.thread;
	import core.time;
	ProgressTracker tracker;
	tracker.showTotal = true;
	tracker.minimumUpdateWait = 1.seconds / 15;
	enum maxProgress = 10;
	enum topLevelItems = 10;
	enum subItemCount = 4;
	foreach (i; 0 .. topLevelItems) {
		auto item = ProgressItem(id: i, name: text("top item ", i), maximum: subItemCount);
		foreach (j; 0 .. subItemCount) {
			item.subItems ~= ProgressItem(id: j, name: text("sub item ", j), maximum: maxProgress);
		}
		tracker.addNewItem(item);
	}
	foreach (topLevelID; 0 .. topLevelItems) with(tracker.matching(topLevelID)) {
		state = ProgressItemState.active;
		status = "doing sub-stuff";
		foreach (subID; 0 .. subItemCount) with(subItems.matching(subID)) {
			foreach (progress; 0 .. maxProgress + 1) {
				current = progress;
				if (progress == maxProgress) {
					state = ProgressItemState.complete;
					status = "complete";
				} else {
					state = ProgressItemState.active;
					status = "doing stuff";
				}
				tracker.updateDisplay();
				//Thread.sleep(1.seconds / 60);
			}
		}
	}
	tracker.updateDisplay(true);
}

debug(rundemo) unittest {
	demo();
}

auto getConsoleDimensions() @trusted {
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

bool isValidConsole() @trusted {
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
