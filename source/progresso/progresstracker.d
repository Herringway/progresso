module progresso.progresstracker;

public import magicalrainbows : RGB = RGB888;
import progresso.bars;

enum ProgressUnit {
	none,
	bytes
}

private struct ProgressItem {
	string name;
	string status;
	UnicodeProgressBar2 bar;
	bool complete;
	ProgressUnit units;
}


struct ProgressTracker {
	private ProgressItem[size_t] items;
	private size_t[] active;
	private size_t[] done;
	bool showTotal;
	bool hideItemProgress;
	bool hideTotalProgress;
	bool totalItemsOnly;
	private ProgressItem total = { name: "Total", bar: { width: 10, showPercentage: false } };
	private uint rewindAmount;
	void addNewItem(size_t id) @safe pure {
		auto item = ProgressItem();
		item.bar.width = 10;
		item.bar.showPercentage = false;
		items[id] = item;
	}
	size_t addNewItem() @safe pure {
		auto item = ProgressItem();
		item.bar.width = 10;
		item.bar.showPercentage = false;
		foreach(id; 0 .. size_t.max) {
			if (id !in items) {
				items[id] = item;
				return id;
			}
		}
		assert(0);
	}
	void setItemStatus(size_t id, string status) @safe pure
		in(id in items, "Progress item not found")
	{
		items[id].status = status;
	}
	void setItemName(size_t id, string name) @safe pure
		in(id in items, "Progress item not found")
	{
		items[id].name = name;
	}
	void setItemMaximum(size_t id, ulong amount) @safe pure
		in(id in items, "Progress item not found")
	{
		items[id].bar.maximum = amount;
		updateTotal();
	}
	void setItemProgress(size_t id, ulong amount) @safe pure
		in(id in items, "Progress item not found")
	{
		items[id].bar.current = amount;
		updateTotal();
	}
	void addItemProgress(size_t id, ulong amount) @safe pure
		in(id in items, "Progress item not found")
	{
		items[id].bar.current += amount;
		if (!totalItemsOnly) {
			total.bar.current += amount;
		}
	}
	void setItemActive(size_t id) @safe pure
		in(id in items, "Progress item not found")
	{
		active ~= id;
	}
	void completeItem(size_t id) @safe pure
		in(id in items, "Progress item not found")
	{
		import std.algorithm.mutation : remove;
		import std.algorithm.searching : countUntil;
		const idx = active.countUntil(id);
		if (idx != -1) {
			active = remove(active, idx);
			done ~= id;
			items[id].bar.complete = true;
			items[id].bar.current = items[id].bar.maximum;
		}
		items[id].complete = true;
		if (totalItemsOnly) {
			total.bar.current++;
		}
		updateTotal();
	}
	void updateDisplay() @safe {
		import std.stdio : write, writef, writeln;
		void printBar(const ProgressItem item, bool advance, bool hideProgress) {
			if (advance) {
				rewindAmount++;
			}
			write(item.bar);
			write(" ");
			if (!hideProgress) {
				final switch (item.units) {
					case ProgressUnit.none:
						write(item.bar.current, "/", item.bar.maximum, " (");
						break;
					case ProgressUnit.bytes:
						writef!"%s/%s ("(PrettyBytesPrinter(item.bar.current), PrettyBytesPrinter(item.bar.maximum));
						break;
				}
			}
			write(item.bar.percentage);
			if (!hideProgress) {
				write(")");
			}
			write(" - ", item.name);
			if (item.status != "") {
				write(" (", item.status, ")");
			}
			writeln();

		}
		if (rewindAmount > 0) {
			foreach (_; 0 ..rewindAmount) {
				write("\x1B[1F\x1B[2K");
			}
		}
		rewindAmount = 0;
		foreach (id; done) {
			printBar(items[id], false, hideItemProgress);
		}
		done = [];
		foreach (id; active) {
			printBar(items[id], true, hideItemProgress);
		}
		if (showTotal) {
			printBar(total, true, hideTotalProgress);
		}
	}
	private void updateTotal() @safe pure {
		total.bar.maximum = 0;
		total.bar.current = 0;
		foreach (const item; items) {
			if (totalItemsOnly) {
				total.bar.maximum++;
				if (item.complete) {
					total.bar.current++;
				}
			} else {
				total.bar.maximum += item.bar.maximum;
				total.bar.current += item.bar.current;
			}
		}
		if (total.bar.current == total.bar.maximum) {
			total.status = "Complete";
		}
	}
	void clear() @safe pure {
		items = null;
		active = [];
		done = [];
	}
	void setTotalColours(RGB from, RGB to, ColourMode mode = ColourMode.time) @safe pure {
		total.bar.from = from;
		total.bar.to = to;
		total.bar.colourMode = mode;
	}
	void setItemColours(size_t idx, RGB from, RGB to, ColourMode mode = ColourMode.time) @safe pure {
		items[idx].bar.from = from;
		items[idx].bar.to = to;
		items[idx].bar.colourMode = mode;
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
	import std.conv : text;
	assert(PrettyBytesPrinter(1023).text == "1023B");
	assert(PrettyBytesPrinter(1024).text == "1KiB");
}

private void demo() {
	import core.thread;
	import core.time;
	import std.conv : text;
	ProgressTracker tracker;
	tracker.showTotal = true;
	foreach (i; 0 .. 100) {
		tracker.addNewItem(i);
		tracker.setItemName(i, i.text);
		tracker.setItemMaximum(i, 100);
	}
	foreach (i; 0 .. 10) {
		foreach(id; 0 .. 10 * 100) {
			const sid = ((i * 10) + (id % 10))	;
			const progress = (id / 10) + 1;
			tracker.addItemProgress(sid, 1);
			tracker.setItemStatus(sid, "Processing");
			if (progress == 1) {
				tracker.setItemActive(sid);
			}
			if (progress == 100) {
				tracker.setItemStatus(sid, "Complete");
				tracker.completeItem(sid);
			}
			tracker.updateDisplay();
			//Thread.sleep(1.seconds / 60);
		}
	}
}
