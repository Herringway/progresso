module progresso.progresstracker;

public import pixelmancy : RGB = RGB888;
import progresso.bars;
import progresso.util;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.conv;
import std.datetime;
import std.exception;
import std.range;
import std.stdio;
import std.string;
import std.typecons;
import std.uni;

enum ProgressUnit {
	none,
	bytes,
	hidden,
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
	bool indeterminateMaximum;
	bool showPercentage = true;
	ProgressUnit unit;
	ColourMode colourMode;
	alias colour = from;
	RGB from;
	RGB to;
	private ubyte donePrinting;
	private bool isRoot;
	void setActive() @safe pure {
		state = ProgressItemState.active;
	}
	void setComplete() @safe pure {
		state = ProgressItemState.complete;
		current = maximum;
	}
	ulong amount() const @safe pure {
		if (state == ProgressItemState.complete) {
			return total;
		}
		if (subItems.length) {
			return subItems.filter!(x => x.state == ProgressItemState.complete).walkLength;
		}
		return current;
	}
	ulong total() const @safe pure {
		if (subItems.length) {
			return subItems.length;
		}
		return maximum;
	}
	ref inout(ProgressItem) matching(ulong id) return inout @safe pure {
		foreach (ref item; subItems) {
			if (item.id == id) {
				return item;
			}
		}
		throw new Exception("No match for "~id.text);
	}
	void addNewItem(ProgressItem newItem) @safe pure {
		subItems ~= newItem;
	}
}

struct ProgressTracker {
	private static struct Options {
		bool showTotal;
		bool hideItemProgress;
		bool hideTotalProgress;
		bool totalItemsOnly;
		Nullable!Duration minimumUpdateWait;
	}
	ProgressItem root = { name: "Total", isRoot: true };
	private Options options;
	private Nullable!MonoTime nextUpdate;
	private size_t lastLinesPrinted;
	ref auto showTotal() => options.showTotal;
	ref auto hideItemProgress() => options.hideItemProgress;
	ref auto hideTotalProgress() => options.hideTotalProgress;
	ref auto totalItemsOnly() => options.totalItemsOnly;
	ref auto minimumUpdateWait() => options.minimumUpdateWait;
	void addNewItem(ProgressItem newItem) @safe pure => root.addNewItem(newItem);
	auto ref matching(ulong id) @safe pure => root.matching(id);
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
		write(printer(lastLinesPrinted, dimensions.width));
		if (lastLinesPrinted > 0) {
			writeln();
		}
	}
	auto printer(Bar = UnicodeProgressBar2)() const {
		size_t _;
		return printer!Bar(_, long.max);
	}
	auto printer(Bar = UnicodeProgressBar2)(out size_t lines, long maxWidth) const {
		struct Printer {
			private const ProgressItem total;
			const Options options;
			void toString(S)(auto ref S sink) const {
				import std.format : formattedWrite;
				bool shouldPrintNewline;
				void printBar(const ProgressItem item, bool hideProgress, int depth, bool linesCount) {
					size_t charCount;
					struct CharCounter {
						void put(const(char)[] text) {
							static import std.range;
							charCount += text.terminalWidth;
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
						bar.showPercentage = false;
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
						// avoid counting the escape sequence
						charCount += bar.width + 2;
						sink.formattedWrite!"%s"(bar);
						if (!hideProgress) {
							final switch (item.unit) {
								case ProgressUnit.hidden:
									break;
								case ProgressUnit.none:
									charCounter.formattedWrite!" %s/%s "(bar.current, bar.maximum);
									break;
								case ProgressUnit.bytes:
									charCounter.formattedWrite!" %s/%s "(PrettyBytesPrinter(bar.current), PrettyBytesPrinter(bar.maximum));
									break;
							}
							if (item.showPercentage) {
								put(charCounter, "(");
							}
						}
						if (item.showPercentage) {
							charCounter.formattedWrite!"%s"(bar.percentage);
							if (!hideProgress) {
								put(charCounter, ")");
							}
							put(charCounter, " -");
						}
						const long maxLabelLength = maxWidth - charCount - 1 - !item.status.byGrapheme.empty * 6;
						charCounter.formattedWrite!" %s"(item.name.abbreviated(maxLabelLength));
						if (item.status != "") {
							const long maxStatusLength = maxWidth - charCount - 3;
							sink.formattedWrite!" (%s)"(item.status.abbreviated(maxStatusLength));
						}
					}
					foreach (subItem; item.subItems) {
						if ((subItem.donePrinting != 2) && (subItem.state == ProgressItemState.complete)) {
							printBar(subItem, hideProgress, depth + 1, !subItem.donePrinting);
						}
					}
					foreach (subItem; item.subItems) {
						if (subItem.state == ProgressItemState.active) {
							printBar(subItem, hideProgress, depth + 1, !subItem.donePrinting);
						}
					}
					if (!item.isRoot || options.showTotal) {
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
			if ((item.state == ProgressItemState.complete) && !item.donePrinting) {
				item.donePrinting++;
			}
			if (item.subItems.length && !item.indeterminateMaximum) {
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
		assert(tracker.printer(unused, 42).text == "    [██████████] 1/1 (100.00%) - Super ...\n[██████████] 1/1 (100.00%) - Super l012...");
	}
	{
		ProgressTracker tracker;
		tracker.addNewItem(ProgressItem(id: 1, maximum: 1, state: ProgressItemState.active, name: "Super l01234567890123456789012345678901234567890g", status: "very l01234567890123456789g"));
		size_t unused;
		assert(tracker.printer(unused, 42).text == "[          ] 0/1 (0.00%) - Super ... (...)");
		tracker.matching(1).subItems ~= ProgressItem(id: 1, maximum: 1, state: ProgressItemState.complete, name: "Super l01234567890123456789012345678901234567890g", status: "very l01234567890123456789g");
		assert(tracker.printer(unused, 42).text == "    [██████████] 1/1 (100.00%) - ... (...)\n[██████████] 1/1 (100.00%) - Supe... (...)");
		assert(tracker.printer(unused, 90).text == "    [██████████] 1/1 (100.00%) - Super l01234567890123456789012345678901234567890g (ve...)\n[██████████] 1/1 (100.00%) - Super l01234567890123456789012345678901234567890g (very l...)");
	}
	{
		ProgressTracker tracker;
		tracker.addNewItem(ProgressItem(id: 1, maximum: 1, state: ProgressItemState.active, name: "🧀🧀🧀🧀🧀 l01234567890123456789012345678901234567890g"));
		size_t unused;
		assert(tracker.printer(unused, 42).text == "[          ] 0/1 (0.00%) - 🧀🧀🧀🧀🧀 l...");
	}
	{
		ProgressTracker tracker;
		tracker.addNewItem(ProgressItem(id: 1, maximum: 1, state: ProgressItemState.active, name: "Test", subItems: [ProgressItem (id: 1, maximum: 1, name: "Subitem test", state: ProgressItemState.active)]));
		assert(tracker.printer().text == "    [          ] 0/1 (0.00%) - Subitem test\n[          ] 0/1 (0.00%) - Test");
		tracker.matching(1).matching(1).state = ProgressItemState.complete;
		assert(tracker.printer().text == "    [██████████] 1/1 (100.00%) - Subitem test\n[██████████] 1/1 (100.00%) - Test");
	}
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
		auto item = ProgressItem(id: i, name: text("top item ", i));
		foreach (j; 0 .. subItemCount) {
			item.subItems ~= ProgressItem(id: j, name: text("sub item ", j), maximum: maxProgress);
		}
		tracker.addNewItem(item);
	}
	foreach (topLevelID; 0 .. topLevelItems) with(tracker.matching(topLevelID)) {
		state = ProgressItemState.active;
		status = "doing sub-stuff";
		foreach (subID; 0 .. subItemCount) with(matching(subID)) {
			state = ProgressItemState.active;
			status = "doing stuff";
			foreach (progress; 0 .. maxProgress + 1) {
				current = progress;
				if (progress == maxProgress) {
					state = ProgressItemState.complete;
					status = "complete";
				}
				tracker.updateDisplay();
				Thread.sleep(1.seconds / 60);
			}
		}
	}
	tracker.updateDisplay(true);
}

debug(rundemo) unittest {
	demo();
}
