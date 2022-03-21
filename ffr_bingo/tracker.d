module ffr_bingo.tracker;

import arsd.cgi;
import arsd.webtemplate;

// FIXME: wtf
import ffr_bingo.main;

class Tracker : WebObject {
	@Skeleton("tracker/skeleton.html"):

	@UrlName("")
	@Template("tracker/layout.html")
	string[string] layout(int roomId = 0) {
		string[string] kv;
		foreach(row; getDatabase.query("SELECT k, v FROM room_tracking WHERE room_id = ?", roomId))
			kv[row["k"]] = row["v"];
		return kv;
	}
}
