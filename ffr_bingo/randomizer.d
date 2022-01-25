module ffr_bingo.randomizer;

import ffr_bingo.card;

Card createRandomCard(Square[] allPossibleSquares, uint seed, bool ignoreRarity, bool ignoreDifficulty) {
	import std.random;

	Mt19937 rng;
	rng.seed(seed);

	Square[][5] poolByDifficulty;
	foreach(square; allPossibleSquares) {
		foreach(i; 0 .. ignoreRarity ? 1 : square.how_common)
			poolByDifficulty[ignoreDifficulty ? 0 : square.easiness] ~= square;
	}

	auto card = new Card();

	int[25] flatDifficultyMatrix = 1;

	// 2 appears in neither diagonal, 3 appears only in one diagonal.
	// 1, 4, and 5 are repeated in diagonals
	// but this ensures all completable options have the same sum
	static immutable int[] weightedDifficultyMatrix = [
		/+
		1, 2, 3, 4, 5,
		3, 4, 5, 1, 2,
		4, 5, 1, 2, 3,
		2, 3, 4, 5, 1,
		5, 1, 2, 3, 4,
		+/
		2, 3, 4, 5, 1,
		4, 5, 1, 2, 3,
		1, 2, 3, 4, 5,
		3, 4, 5, 1, 2,
		5, 1, 2, 3, 4,
	];

	// thx deadpulse for noting just shifting the rows down by two should maintain the count while shuffling things a lil

	foreach(index, expected; ignoreDifficulty ? flatDifficultyMatrix : weightedDifficultyMatrix) {
		auto pool = poolByDifficulty[expected - 1]; // zero based indexing

		/+
		only choose from non mutually exclusive groups for this square, so filter it
		but doing it in a separate variable because in the end, we keep them in the
		overall pool. Consider "Never promote" and "Promote as soon as possible". Well,
		you arguably could fulfil both of those because if you have never promote, it is
		never possible to promote! So if you had both they'd just check each other instantly.

		Maybe a better example is "Take 3 white mages" and "Take 3 black mages". Obviously
		can't do both in a single set. But it could be in different parts of the board, so
		your opponent might be forced to take the white mages, while they force you to take
		the black mages.

		Thus making it filter for this thing, but not necessarily globally.
		+/
		auto filteredPool = pool.filterOutMutuallyExclusive(card, cast(int) index % 5, cast(int) index / 5);
		auto selected = filteredPool[uniform(0, filteredPool.length, rng)];

		card[index] = selected;

		poolByDifficulty[expected - 1] = pool.remove(item => item is selected);
	}

	return card;
}

Square[] filterOutMutuallyExclusive(Square[] pool, Card card, int x, int y) {
	// mutex checks need to be done if x is the same, y is the same, or if x == y or x == 4-y

	string[] excludes;

	void check(int x1, int y2) {
		auto square = card[x1, y2];
		if(square !is null && square.mutex_group.length)
			excludes ~= square.mutex_group;
	}

	foreach(ycheck; 0 .. 5)
		check(x, ycheck);
	foreach(xcheck; 0 .. 5)
		check(xcheck, y);
	if(x == y)
		foreach(coord; 0 .. 5)
			check(coord, coord);
	if(x == 4 - y)
		foreach(coord; 0 .. 5)
			check(4 - coord, coord);

	if(excludes.length == 0)
		return pool;
	
	Square[] keep;
	item_loop: foreach(item; pool) {
		if(item.mutex_group.length == 0) {
			keep ~= item;
		} else {
			foreach(exclude; excludes)
				if(item.mutex_group == exclude)
					continue item_loop;
			keep ~= item;

		}
	}

	return keep;
}

Square[] remove(Square[] group, scope bool delegate(Square s) dg) {
	for(int index = 0; index < group.length; index++) {
		if(dg(group[index])) {
			group[index] = group[$-1];
			group = group[0 .. $-1];
			index--;
		}
	}
	return group;
}

/+
	DIFFICULTY

	1 2 3 4 5
	3 4 5 1 2
	4 5 1 2 3
	2 3 4 5 1
	5 1 2 3 4

	Can vary a bit but will bias toward these values.

	50% - exact
	25% - consider + or - 1
	12.5% - consider + or - 2
	6.25% - consider + or - 3
	3.125 % - consider + or - 4

	other 3.125% - just go back to exact


	UNLESS there's mutex squares like "take 3 fighters" and "take 3 black mages" which can never be done together. If they are all in the same tier and you don't randomize the difficulty it can ensure all things are indeed beatable.


	RARITY / COMMONNESS

	5 = pulled 5/15 of the time
	4 = pulled 4/15
	3 = pulled 3/15
	2 = pulled 2/15
	1 = pulled 1/15

	It simply repeats the item by commonness into the random pool the given number of times as long as it is available.
+/

