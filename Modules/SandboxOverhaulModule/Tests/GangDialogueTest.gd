extends SceneTree

# Run: godot --path <project dir> -s res://Modules/SandboxOverhaulModule/Tests/GangDialogueTest.gd --quit
# What gang leaders say and the plain information next to it: first person for the leader, speech without reward data, one short panel of facts, the three commitments of each gang,
# and the Side Tasks wording. No game needed.

const DialogueScript = preload("res://Modules/SandboxOverhaulModule/Gangs/GangDialogue.gd")

var failures = 0

func check(cond: bool, msg: String):
	if(!cond):
		failures += 1
		print("FAIL: " + msg)

func _init():
	# Who leads
	check(DialogueScript.whoLeads(true, "Simone", "Ironhand") == "I am in charge of Ironhand.", "the leader answers in the first person")
	check(DialogueScript.whoLeads(false, "Simone", "Ironhand") == "Simone is in charge of Ironhand.", "a member names the leader")
	check(DialogueScript.whoLeads(false, "Simone", "The Hush Market") == "Simone is in charge of The Hush Market." and DialogueScript.whoLeads(true, "Marvin", "The Collar Circle") == "I am in charge of The Collar Circle.", "the same wording for every gang")
	check(DialogueScript.whoLeads(false, "", "Ironhand") == "Nobody, right now.", "no leader")

	# The three introductory jobs
	var ctx = {"gang": "Ironhand", "leader": "Simone", "target": "Ashlee", "targetGang": "", "recipientGang": "", "amount": 0}
	var ironhand = DialogueScript.offerSpeech("ironhand", "defeat", true, ctx)
	check(ironhand == "You want a place with Ironhand? Prove you can handle yourself. Ashlee runs with one of our rivals. Put them down, then come back to me.", "Ironhand's speech: " + ironhand)
	var hush = DialogueScript.offerSpeech("hushmarket", "courier", true, {"gang": "The Hush Market", "target": "Bo", "recipientGang": "The Collar Circle", "amount": 8})
	check(hush.find("8 credits to Bo of The Collar Circle") != -1 and hush.find("Quietly.") != -1 and hush.find("Eligib") == -1, "the Hush Market's courier speech names the payment and the recipient: " + hush)
	var collar = DialogueScript.offerSpeech("collarcircle", "capture", true, {"gang": "The Collar Circle", "target": "Cy", "targetGang": "Ironhand"})
	check(collar.find("Beat them, then bring them to me.") != -1 and collar.find("Cy of Ironhand") != -1, "the Collar Circle's capture speech: " + collar)
	for speech in [ironhand, hush, collar]:
		for banned in ["Standing", "Reward", "Failure", "credits reward", "introductory", "hours"]:
			check(speech.find(banned) == -1, "speech never recites '" + banned + "': " + speech)

	# The panel
	var offer = {"type": "defeat", "intro": true, "reward": 0, "standing": 10, "penalty": 8, "created": 1000, "deadline": 1000 + 48 * 3600, "state": "offered", "stage": "", "amount": 0, "item": ""}
	var panel = DialogueScript.offerPanel(offer, ctx)
	check(panel == "[b]Objective:[/b] Defeat Ashlee\n[b]Reward:[/b] Eligibility to join Ironhand; Standing +10\n[b]Failure:[/b] Standing −8\n[b]Time limit:[/b] 48 hours", "the panel is four short lines: " + panel)
	var paid = DialogueScript.offerPanel({"type": "defeat", "intro": false, "reward": 6, "standing": 8, "penalty": 8, "created": 0, "deadline": 48 * 3600}, ctx)
	check(paid.find("[b]Reward:[/b] 6 credits; Standing +8") != -1 and paid.find("Eligibility") == -1, "an ordinary job pays credits and standing")
	check(DialogueScript.remainingText(100 + 47 * 3600, 100) == "About 47 hours remaining." and DialogueScript.remainingText(100 + 1800, 100) == "Less than an hour remaining." and DialogueScript.remainingText(50, 100) == "Time is up." and DialogueScript.remainingText(100 + 3600, 100) == "About 1 hour remaining.", "time left wording")

	# Accepting, reporting, the code, welcoming
	for gid in ["ironhand", "hushmarket", "collarcircle"]:
		check(DialogueScript.acceptSpeech(gid).begins_with("Good.") and DialogueScript.acceptSpeech(gid).find("Come back when it is done.") != -1, gid + ": accepting is a short answer")
		check(DialogueScript.codeOf(gid).size() == 3, gid + ": three commitments")
		check(DialogueScript.welcomeSpeech(gid).begins_with("Then you ") and DialogueScript.notYetSpeech(gid) != "" and DialogueScript.initiationSpeech(gid) != "", gid + ": initiation, welcome and 'not yet' are all written")
		check(DialogueScript.reportSpeech(gid, "defeat", true, {"target": "Ashlee"}).find("Ashlee") != -1, gid + ": the report is answered")
	check(DialogueScript.codeOf("ironhand") == ["Stand beside fellow members.", "Show strength against rivals.", "Put Ironhand before outsiders."], "Ironhand's code")
	check(DialogueScript.codeOf("hushmarket") == ["Keep the gang's secrets.", "Honour bargains made through the gang.", "Protect its trade and members."], "the Hush Market's code")
	check(DialogueScript.codeOf("collarcircle") == ["Respect the gang hierarchy.", "Help enforce its claims.", "Protect members and controlled assets."], "the Collar Circle's code")
	check(DialogueScript.welcomeSpeech("ironhand") == "Then you are Ironhand now. Stand with us and we will stand with you.", "Ironhand's welcome")
	check(DialogueScript.line("Simone", "sim", "Hello.") == "[say=sim]Hello.[/say]", "a speech line is only the say tag (it writes the name itself)")

	# Side Tasks
	var active = {"type": "defeat", "intro": true, "state": "active", "stage": "", "deadline": 100 + 47 * 3600, "amount": 0, "item": ""}
	var tctx = {"gang": "Ironhand", "leader": "Simone", "target": "Ashlee", "targetGang": "", "clue": "Members of The Hush Market usually gather at the laundry."}
	check(DialogueScript.taskTitle(active, tctx) == "Ironhand Initiation", "the entry is titled by gang and kind")
	var lines = DialogueScript.taskLines(active, tctx, 100)
	check(lines == ["About 47 hours remaining.", "Members of The Hush Market usually gather at the laundry.", "Defeat Ashlee, a member of a rival gang, then report back to Simone."], "the active entry (shown newest first by the log): " + str(lines))
	var ready = active.duplicate()
	ready["state"] = "ready"
	var readyLines = DialogueScript.taskLines(ready, tctx, 100)
	check(readyLines == ["Status: ready to report.", "Ashlee has been defeated. Report back to Simone."], "the ready entry: " + str(readyLines))
	var courier = {"type": "courier", "intro": true, "state": "active", "stage": "", "deadline": 1000, "amount": 8, "item": ""}
	check(DialogueScript.taskLines(courier, {"gang": "The Hush Market", "leader": "Marvin", "target": "Bo", "recipientGang": "Ironhand"}, 0)[1] == "Take 8 credits to Bo of Ironhand, then report back to Marvin.", "the courier entry")
	check(DialogueScript.taskTitle({"intro": false}, {"gang": "Ironhand"}) == "Ironhand job", "an ordinary job's title")

	print("GangDialogueTest: " + ("PASS" if failures == 0 else str(failures) + " failure(s)"))
	quit(1 if failures > 0 else 0)
