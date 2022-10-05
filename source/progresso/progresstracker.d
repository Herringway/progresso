module progresso.progresstracker;

import progresso.bars;

private struct ProgressItem {
	string name;
	string status;
	UnicodeProgressBar2 bar;
	bool complete;
}

struct ProgressTracker {
	private ProgressItem[size_t] items;
	private size_t[] active;
	private size_t[] done;
	bool showTotal;
	bool hideProgress;
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
		items[id].bar.max = amount;
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
			if (items[id].bar.max == 0) {
				items[id].bar.max = 1;
			}
			items[id].bar.current = items[id].bar.max;
		}
		items[id].complete = true;
		if (totalItemsOnly) {
			total.bar.current++;
		}
		updateTotal();
	}
	void updateDisplay() @safe {
		import std.stdio : write, writeln;
		void printBar(const ProgressItem item, bool advance) {
			if (advance) {
				rewindAmount++;
			}
			write(item.bar);
			write(" ");
			if (!hideProgress) {
				write(item.bar.current, "/", item.bar.max, " (");
			}
			write(item.bar.percentage);
			if (!hideProgress) {
				write(")");
			}
			write(" - ", item.name);
			write(" (", item.status, ")");
			writeln();

		}
		if (rewindAmount > 0) {
			foreach (_; 0 ..rewindAmount) {
				write("\x1B[1F\x1B[2K");
			}
		}
		rewindAmount = 0;
		foreach (id; done) {
			printBar(items[id], false);
		}
		done = [];
		foreach (id; active) {
			printBar(items[id], true);
		}
		if (showTotal) {
			printBar(total, true);
		}
	}
	private void updateTotal() @safe pure {
		total.bar.max = 0;
		total.bar.current = 0;
		foreach (const item; items) {
			if (totalItemsOnly) {
				total.bar.max++;
				if (item.complete) {
					total.bar.current++;
				}
			} else {
				total.bar.max += item.bar.max;
				total.bar.current += item.bar.current;
			}
		}
		if (total.bar.current == total.bar.max) {
			total.status = "Complete";
		}
	}
	void clear() @safe pure {
		items = null;
		active = [];
		done = [];
	}
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
