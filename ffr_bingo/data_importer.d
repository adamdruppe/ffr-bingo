module ffr_bingo.data_importer;

import ffr_bingo.card;

// This is for importing the paste bin definitions from winter dab
Square[] importText(string text) {
	import std.string, std.conv;

	int currentEasiness;

	Square[] list;
	foreach(line; text.splitLines) {
		line = line.strip;
		if(line.length == 0)
			continue;
		if(line.length <= 2) {
			auto difficulty = to!int(line);

			currentEasiness = 4 - (difficulty-1) / 5;
			continue;
		}

		auto square = new Square();
		auto dash = line.indexOf(" - ");

		if(line.length && line[$-1] == '}') {
			auto pos = cast(int) line.length - 1;
			while(pos && line[pos] != '{')
				pos--;
			if(pos == 0)
				throw new Exception("Import data had an unmatched } at the end of a line which confuses the importer.");

			square.mutex_group = line[pos + 1 .. $ - 1];
			line = line[0 .. pos];
		}

		if(dash == -1) {
			square.name = line;
		} else {
			square.name = line[0 .. dash];
			square.details = line[dash + 3 .. $];
		}
		square.easiness = currentEasiness;
		square.how_common = 1;

		square.starts_game_checked = line.indexOf("Defaults to completed.") != -1;

		list ~= square;
	}

	return list;
}
