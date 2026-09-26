-- fogona: never link a media-role loopback's output into another media-role
-- loopback (feedbackd's media-role-nodes.conf).
--
-- A card profile switch (callaudiod at every call start and end) leaves a
-- moment with no ALSA sink, and the default sink then falls back to one of
-- the role loopback sinks. find-default-target links the loopbacks' outputs
-- there, e.g. Multimedia -> Alerts, and the link outlives the gap. The
-- Alerts role (priority 100, lower priority "cork") is then active for
-- good and corks every ringtone. With no target the loopback output waits
-- for the real sink instead.

lutils = require ("linking-utils")
cutils = require ("common-utils")
log = Log.open_topic ("s-linking")

SimpleEventHook {
  name = "linking/fogona-role-loopback-no-chain",
  after = { "linking/find-defined-target",
            "linking/find-filter-target",
            "linking/find-media-role-target",
            "linking/find-media-role-sink-target",
            "linking/find-default-target",
            "linking/find-best-target",
            "linking/get-filter-from-target" },
  before = "linking/prepare-link",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  execute = function (event)
    local _, _, si, si_props, _, target =
        lutils:unwrap_select_target_event (event)

    if not target or si_props ["media.role"] ~= "Loopback" then
      return
    end

    if cutils.parseBool (target.properties ["policy.role-based.target"]) then
      log:info (si, string.format ("... not linking %s into role loopback %s",
          tostring (si_props ["node.name"]),
          tostring (target.properties ["node.name"])))
      event:set_data ("target", nil)
    end
  end
}:register ()
