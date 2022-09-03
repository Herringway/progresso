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
	bool totalItemsOnly;
	private ProgressItem total = { name: "Total", bar: { width: 10, showPercentage: true } };
	private uint rewindAmount;
	void addNewItem(size_t id) @safe pure {
		auto item = ProgressItem();
		item.bar.width = 10;
		item.bar.showPercentage = true;
		items[id] = item;
	}
	size_t addNewItem() @safe pure {
		auto item = ProgressItem();
		item.bar.width = 10;
		item.bar.showPercentage = true;
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
		active = remove(active, idx);
		done ~= id;
		items[id].complete = true;
		if (totalItemsOnly) {
			total.bar.current++;
		}
	}
	void updateDisplay() @safe {
		import std.stdio : writef, writeln;
		if (rewindAmount > 0) {
			writef("\x1B[%dF", rewindAmount);
		}
		rewindAmount = 0;
		foreach (id; done) {
			writeln(items[id].bar, " - ", items[id].name, " (", items[id].status, ")");
		}
		done = [];
		foreach (id; active) {
			rewindAmount++;
			writeln(items[id].bar, " - ", items[id].name, " (", items[id].status, ")");
		}
		if (showTotal) {
			rewindAmount++;
			writeln(total.bar, " - ", total.name, " (", total.status, ")");
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
	}
	void clear() @safe pure {
		items = null;
		active = [];
		done = [];
	}
}

unittest {
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
