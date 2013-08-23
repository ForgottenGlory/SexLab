scriptname sslActorAlias extends ReferenceAlias

SexLabFramework property SexLab auto
sslSystemResources property Data auto
sslSystemConfig property Config auto

bool Active
actor ActorRef
sslThreadController Controller

; Actor Information
sslBaseVoice property Voice auto hidden
float VoiceDelay
float VoiceStrength
bool IsSilent

int VoiceInstance

bool IsPlayer
bool IsVictim
bool IsScaled

float Scale


form[] EquipmentStorage

;/-----------------------------------------------\;
;|	Preparation Functions                        |;
;\-----------------------------------------------/;

function PrepareActor()
	if IsPlayer
		Game.ForceThirdPerson()
		;Game.DisablePlayerControls(true, true, false, false, true, false, false, true, 0)
		;Game.SetInChargen(false, true, true)
		Game.SetPlayerAIDriven()
		; Enable hotkeys, if needed
		if Config.bDisablePlayer && IsVictim
			Controller.autoAdvance = true
		else
			SexLab._EnableHotkeys(Controller.tid)
		endIf
		; Toggle TCL if enabled and player present
		if Config.bEnableTCL
			Debug.ToggleCollisions()
		endIf
	else
		ActorRef.SetRestrained()
		ActorRef.SetDontMove()
		ActorRef.SetAnimationVariableBool("bHumanoidFootIKDisable", true)
	endIf
	if ActorRef.IsWeaponDrawn()
		ActorRef.SheatheWeapon()
	endIf
	; Start DoNothing package
	ActorRef.SetFactionRank(SexLab.AnimatingFaction, 1)
	TryToEvaluatePackage()
	; Sexual animations only
	if Controller.Animation.IsSexual()
		; Strip Actor
		form[] equipment = SexLab.StripSlots(ActorRef, Controller.GetStrip(ActorRef), true)
		StoreEquipment(equipment)
		; Make Erect
		if SexLab.sosEnabled && Controller.Animation.GetGender(Controller.GetPosition(ActorRef)) < 1
			Debug.SendAnimationEvent(ActorRef, "SOSFastErect")
		endIf
	endIf
	; Scale actor is enabled
	if Controller.ActorCount > 1 && Config.bScaleActors
		IsScaled = true

		float display = ActorRef.GetScale()
		ActorRef.SetScale(1.0)
		float base = ActorRef.GetScale()
		
		Scale = ( display / base )
		ActorRef.SetScale(Scale)
		ActorRef.SetScale(1.0 / base)
	endIf
	; Set into aniamtion ready state
	GoToState("Ready")
endFunction

function ResetActor()
	UnregisterForUpdate()
	GoToState("")
	; Reset to starting scale
	if IsScaled
		ActorRef.SetScale(Scale)
	endIf
	; Reset openmouth
	ActorRef.ClearExpressionOverride()
	; Enable movement
	if IsPlayer
		if Config.bEnableTCL
			Debug.ToggleCollisions()
		endIf
		SexLab._DisableHotkeys()
		;Game.SetInChargen(false, false, false)
		Game.SetPlayerAIDriven(false)
		;Game.EnablePlayerControls()
		SexLab.UpdatePlayerStats(Controller.Animation, Controller.GetTime(), Controller.Positions, Controller.GetVictim())
	else
		ActorRef.SetAnimationVariableBool("bHumanoidFootIKEnable", true)
		ActorRef.SetDontMove(false)
		ActorRef.SetRestrained(false)
	endIf
	; Remove from animation faction
	ActorRef.RemoveFromFaction(SexLab.AnimatingFaction)
	; Make flaccid
	if SexLab.sosEnabled && Controller.Animation.GetGender(Controller.GetPosition(ActorRef)) < 1
		Debug.SendAnimationEvent(ActorRef, "SOSFlaccid")
	endIf
	; Unstrip
	if !ActorRef.IsDead() && !ActorRef.IsBleedingOut()
		SexLab.UnstripActor(ActorRef, EquipmentStorage, Controller.GetVictim())
	endIf
	; Reset Idle
	if !Config.bRagdollEnd
		Debug.SendAnimationEvent(ActorRef, "IdleForceDefaultState")
	else
		ActorRef.PushActorAway(ActorRef, 1)
	endIf
endFunction

function PlayAnimation(sslBaseAnimation Animation, int position, int stage)
	; Play Idle
	Debug.SendAnimationEvent(ActorRef, Animation.FetchPositionStage(position, stage))
	; Open Mouth
	if Animation.UseOpenMouth(position, stage)
		ActorRef.SetExpressionOverride(16, 100)
	else
		ActorRef.ClearExpressionOverride()
	endIf
	; Send SOS event
	if SexLab.sosEnabled && Animation.GetGender(position) < 1
		Debug.SendAnimationEvent(ActorRef, "SOSBend"+Animation.GetSchlong(position, stage))
	endif
endfunction

function SetAlias(sslThreadController ThreadView)
	_Init()
	TryToStopCombat()
	ActorRef = GetReference() as actor
	Controller = ThreadView
	IsPlayer = ActorRef == SexLab.PlayerRef
	IsVictim = ActorRef == ThreadView.GetVictim()
endFunction

;/-----------------------------------------------\;
;|	Storage Functions                             |;
;\-----------------------------------------------/;

function StoreEquipment(form[] equipment)
	if equipment.Length < 1
		return
	endIf
	; Addon existing storage
	int i
	while i < EquipmentStorage.Length
		equipment = sslUtility.PushForm(EquipmentStorage[i], equipment)
		i += 1
	endWhile
	; Save new storage
	EquipmentStorage = equipment
endFunction


; TODO: Needs to be integrated with ChangeAnimtion() in contorller, or maybe PlayAnimation() here.
function ChangeStage(sslBaseAnimation Animation, int position, int stage)
	if !Active || ActorRef == none
		return
	endIf

	; Update Strength
	VoiceStrength = (stage as float) / (Animation.StageCount() as float)
	if Animation.StageCount() == 1 && stage == 1
		VoiceStrength = 0.50
	endIf
	; Base Delay
	if SexLab.GetGender(ActorRef) < 1
		VoiceDelay = Config.fMaleVoiceDelay
	else
		VoiceDelay = Config.fFemaleVoiceDelay
	endIf
	; Stage Delay
	if stage > 1
		VoiceDelay = (VoiceDelay - (stage * 0.8)) + Utility.RandomFloat(-0.3, 0.3)
	endIf
	; Min 1.3 delay
	if VoiceDelay < 1.3
		VoiceDelay = 1.3
	endIf
	; Update Silence
	IsSilent = Animation.IsSilent(position, stage)
endFunction

;/-----------------------------------------------\;
;|	Animation/Voice Loop                         |;
;\-----------------------------------------------/;

state Ready
	event OnBeginState()
		UnregisterForUpdate()
	endEvent
	function StartAnimating()
		Active = true
		ChangeStage(Controller.Animation, Controller.Positions.Find(ActorRef), Controller.Stage)
		GoToState("Animating")
		RegisterForSingleUpdate(Utility.RandomFloat(0.0, 0.8))
	endFunction
endState

state Animating
	event OnUpdate()
		if !Active || ActorRef == none
			return
		endIf

		if ActorRef.IsDead() || ActorRef.IsBleedingOut() || !ActorRef.Is3DLoaded()
			Controller.EndAnimation(true)
			return
		endIf

		if !IsSilent
			if VoiceInstance > 0
				Sound.StopInstance(VoiceInstance)
			endIf
			VoiceInstance = Voice.Moan(ActorRef, VoiceStrength, IsVictim)
			Sound.SetInstanceVolume(VoiceInstance, Config.fVoiceVolume)
		endIf

		RegisterForSingleUpdate(VoiceDelay)
	endEvent
endState

;/-----------------------------------------------\;
;|	Actor Callbacks                              |;
;\-----------------------------------------------/;

function ActorEvent(string callback, int position)
	;Debug.TraceAndBox("Sending Event "+callback+": "+ActorRef)
	RegisterForModEvent(callback, "On"+callback)
	SendModEvent(callback)
endFunction

event OnStartThread(string eventName, string actorSlot, float argNum, form sender)
	;Debug.TraceAndBox("OnStartThread: "+ActorRef)
	PrepareActor()
	UnregisterForModEvent(eventName)
endEvent

event OnEndThread(string eventName, string actorSlot, float argNum, form sender)
	ResetActor()
	UnregisterForModEvent(eventName)
endEvent

;/-----------------------------------------------\;
;|	Misc Functions                               |;
;\-----------------------------------------------/;

function _Init()
	ActorRef = none
	Controller = none
	Voice = none

	IsScaled = false

	form[] formDel
	EquipmentStorage = formDel
endFunction

event OnPackageStart(package newPackage)
	Debug.Trace("Evaluated "+GetActorRef()+"'s package to "+newPackage)
endEvent

function StartAnimating()
	Debug.TraceAndbox("Null start: "+ActorRef)
endFunction