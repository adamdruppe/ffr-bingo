module ffr_bingo.card;

import std.conv;

class Square {
	int id;
	string name;
	string details;
	int easiness;
	int how_common;
	bool starts_game_checked;

	string mutex_group;

	this() {}

	this(string[string] row) {
		this.id = row["id"].to!int;
		this.name = row["name"];
		this.details = row["details"];
		this.easiness = row["easiness"].to!int;
		this.how_common = row["how_common"].to!int;
		this.starts_game_checked = row["starts_game_checked"] == "1";
		this.mutex_group = row["mutex_group"];
	}


	import arsd.dom;
	Element toHtml() {
		auto div = Element.make("div").addClass("bingo-square");

		div.innerText = this.name;
		div.dataset.details = this.details;
		div.dataset.squareId = this.id.to!string;
		div.dataset.mutexGroup = mutex_group;
		div.dataset.difficulty = (4 - this.easiness + 1).to!string;
		div.dataset.how_common = this.how_common.to!string;

		debug(difficulty) {
			div.appendText(" (" ~ to!string(easiness) ~ ")");
		}

		return div;
	}

}

final class InGameSquare : Square {
	this(string[string] row) {
		super(row);

		state = row["player_checked_state"].to!uint;
	}

	private this(Square base) {
		Square this_ = this;
		this_.tupleof = base.tupleof;

		if(this.starts_game_checked)
			this.state = uint.max;
	}

	void setByPlayer(int player, bool yes) {
		state &= ~(1 << player);
		if(yes) state |= (1 << player);
	}

	bool isSetByPlayer(int player) {
		return (state & (1 << player)) ? true : false;
	}

	private uint state;

	import arsd.dom;
	override Element toHtml() {
		auto div = super.toHtml();

		div.dataset.playerState = to!string(state);

		if(isSetByPlayer(0))
			div.addClass("player-0-checked");
		if(isSetByPlayer(1))
			div.addClass("player-1-checked");

		return div;
	}
}

final class Card {
	this() {
		// set them all to a generic blank one to avoid null
		squares_[] = new InGameSquare(new Square());
	}

	immutable width = 5;
	immutable height = 5;

	public string[] player_selections;

	InGameSquare opIndex(size_t index) {
		return squares_[index];
	}

	InGameSquare opIndex(int x, int y) {
		return squares_[y * 5 + x];
	}

	InGameSquare opIndexAssign(Square what, size_t index) {
		return squares_[index] = new InGameSquare(what);
	}

	InGameSquare opIndexAssign(InGameSquare what, size_t index) {
		return squares_[index] = what;
	}

	InGameSquare opIndexAssign(Square what, int x, int y) {
		return squares_[y * 5 + x] = new InGameSquare(what);

	}

	/++
		card[x, y] &= player1; // clear
		card[x, y] |= player1; // set
		card[x, y] ^= player1; // toggle
	+/
	void opIndexOpAssign(string op)(int player, int x, int y) {
		InGameSquare s = this[x, y];
		mixin("s.state " ~ op ~ "= (1 << player);");
	}

	private InGameSquare[5 * 5] squares_;

	int opApply(scope int delegate(size_t idx, InGameSquare sq) dg) {
		foreach(idx, s; squares_) {
			if(auto i = dg(idx, s))
				return i;
		}
		return 0;
	}

	import arsd.dom;
	Element toHtml() {
		import std.conv;
		auto table = cast(Table) Element.make("table").addClass("bingo-card");

		table.appendHeaderRow("TL-BR", "C-1", "C-2", "C-3", "C-4", "C-5");

		foreach(row; 0 .. 5)
			table.appendRow(
				table.th("R-" ~ to!string(row + 1)),
				this[0, row].toHtml,
				this[1, row].toHtml,
				this[2, row].toHtml,
				this[3, row].toHtml,
				this[4, row].toHtml
			);

		auto descHolder = table.appendFooterRow(table.th("BL-TR").setAttribute("class", "diagonal"), Element.make("div", "", "description")).children[1];
		descHolder.className = "description-holder";
		descHolder.attrs.colspan = "5";
		descHolder.attrs.rowspan = "2";
		table.appendFooterRow(table.td("\&nbsp;").setAttribute("class", "spacer"));

		if(player_selections.length) {
			foreach(th; table.querySelectorAll("th")) {
				uint mask = 0;
				foreach(idx, selection; player_selections)
					if(selection == th.textContent) {
						// you choose it for the next player in the list
						auto selectedFor = cast(int) idx;
						selectedFor++;
						if(selectedFor == player_selections.length)
							selectedFor = 0;

						mask |= (1 << selectedFor);
					}

				th.dataset.playerState = mask.to!string;
			}
		}

		return table;
	}
}
