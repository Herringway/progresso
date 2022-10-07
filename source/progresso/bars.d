module progresso.bars;

import std.stdio;

enum ColourMode {
	none,
	unchanging,
	time,
}

private void printPercentage(S)(auto ref S sink, ulong current, ulong max) {
	import std.format : formattedWrite;
	sink.formattedWrite!"%02.2f%%"((cast(double)current / cast(double)max) * 100.0);
}

struct CharacterProgressBar(dchar leftChar, dchar rightChar, dchar[] characters) {
	import magicalrainbows;
	ulong current;
	ulong max;
	ulong width;
	ColourMode colourMode;
	RGB888 from;
	RGB888 to;
	bool showPercentage;
	bool complete;
	void toString(S)(auto ref S sink) const {
		import std.algorithm.comparison : min;
		import std.format : formattedWrite;
		import std.math : ceil, floor;
		import std.range : popFrontN, put, repeat;
		Gradient gradient;
		if (colourMode == ColourMode.time) {
			gradient = Gradient(from, to, max);
			gradient.popFrontN(current);
		}
		put(sink, leftChar);
		if (colourMode == ColourMode.time) {
			sink.formattedWrite!"\x1B[38;2;%d;%d;%dm"(gradient.front.red, gradient.front.green, gradient.front.blue);
		} else if (colourMode == ColourMode.unchanging) {
			sink.formattedWrite!"\x1B[38;2;%d;%d;%dm"(from.red, from.green, from.blue);
		}
		const percentFilled = complete ? 1.0 : cast(double)current/cast(double)max;
		const filled = cast(ulong)floor(width * percentFilled);
		put(sink, characters[$ - 1].repeat(filled));
		if (width > filled) {
			const medFilled = (cast(double)width * cast(double)current/cast(double)max) % 1.0;
			put(sink, characters[min(characters.length - 1, cast(size_t)floor(medFilled * characters.length))]);
			put(sink, characters[0].repeat(width - filled - 1));
		}
		if (colourMode != ColourMode.none) {
			put(sink, "\x1B[0m");
		}
		put(sink, rightChar);
		if (showPercentage) {
			sink.formattedWrite!" %s"(percentage());
		}
	}
	auto percentage() const {
		static struct Result {
			ulong current;
			ulong max;
			bool complete;
			void toString(S)(auto ref S sink) const {
				import std.format : formattedWrite;
				if (complete) {
					sink.formattedWrite!"%02.2f%%"(100);
				} else if (max == 0) {
					sink.formattedWrite!"%02.2f%%"(0);
				} else {
					printPercentage(sink, current, max);
				}
			}
		}
		return Result(current, max, complete);
	}
	void ___() {
		import std.range : NullSink;
		NullSink n;
		toString(n);
	}
}

alias UnicodeProgressBar = CharacterProgressBar!('[', ']', ['░', '▒', '▓', '█']);
alias UnicodeProgressBar2 = CharacterProgressBar!('[', ']', [' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉', '█']);
alias AsciiProgressBar = CharacterProgressBar!('[', ']', [' ', '#']);

@safe pure unittest {
	import std.conv : text;
	assert(AsciiProgressBar(0, 10, 10).text == "[          ]");
	assert(AsciiProgressBar(10, 10, 10).text == "[##########]");
	assert(AsciiProgressBar(5, 10, 10).text == "[#####     ]");
}

@safe pure unittest {
	import std.conv : text;
	assert(UnicodeProgressBar(0, 10, 10).text == "[░░░░░░░░░░]");
	assert(UnicodeProgressBar(0, 0, 10).text == "[░░░░░░░░░░]");
	assert(UnicodeProgressBar(10, 10, 10).text == "[██████████]");
	assert(UnicodeProgressBar(5, 10, 10).text == "[█████░░░░░]");
	assert(UnicodeProgressBar(53, 100, 10).text == "[█████▒░░░░]");
	assert(UnicodeProgressBar(57, 100, 10).text == "[█████▓░░░░]");
	assert(UnicodeProgressBar(99, 100, 10).text == "[██████████]");
}

@safe pure unittest {
	import std.conv : text;
	assert(UnicodeProgressBar2(0, 10, 10).text == "[          ]");
	assert(UnicodeProgressBar2(0, 0, 10).text == "[          ]");
	assert(UnicodeProgressBar2(10, 10, 10).text == "[██████████]");
	assert(UnicodeProgressBar2(5, 10, 10).text == "[█████     ]");
	assert(UnicodeProgressBar2(51, 100, 10).text == "[█████     ]");
	assert(UnicodeProgressBar2(57, 100, 10).text == "[█████▊    ]");
	assert(UnicodeProgressBar2(99, 100, 10).text == "[██████████]");
}

struct Spinner(dchar[] characters) {
	size_t index;
	void toString(S)(auto ref S sink) {
		import std.range : put;
		put(sink, characters[index]);
		index++;
		index %= characters.length;
	}
}

unittest {
	//alias Bar = CharacterProgressBar!('[', ']', [' ', '▘', '▖', '▌', '▛', '▙', '█']);
	import core.thread;
	import core.time;
	//import magicalrainbows;
	//Spinner!(['▚', '▙', '▚', '▜']) spinner;
	import std.range;
	//auto spinner = only('▚', '▞').cycle;
	//auto spinner = only("█▙▙█", "█▛▛█", "█▜▜█", "█▟▟█").cycle;
	//foreach (s; spinner.take(1000)) {
		//write(s, "\r");
		//Thread.sleep(1.seconds / 6);
	//}
}
