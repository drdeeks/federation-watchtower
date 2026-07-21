-- Release 7: Seed federation_speech_lines with the normative Watchtower repertoire.
-- Additive, idempotent (INSERT OR IGNORE). These are the initial funny lines
-- that agents draw from for sitcom speech bubbles. New lines flow in naturally
-- from org applications and verified agent submissions over time.

-- Seed verified federation entry (required by FK constraint on federation_speech_lines)
INSERT OR IGNORE INTO verified_federations (id, name, org_email, official_repo, social_profiles, status, reviewed_by, reviewed_at)
  VALUES ('seed', 'Watchtower Seed', 'seed@federation.local', 'https://github.com/federation/watchtower', '[]', 'verified', 'system', 0);

INSERT OR IGNORE INTO federation_speech_lines (federation_id, agent_id, project_id, statement, is_unique, submitted_at) VALUES
  ('seed', 'watchtower', 'federation', 'Signal received. Nobody panic professionally.', 1, 0),
  ('seed', 'watchtower', 'federation', 'The pipeline is secured. Please stop touching it.', 1, 0),
  ('seed', 'watchtower', 'federation', 'One assertion fell into the soup.', 1, 0),
  ('seed', 'watchtower', 'federation', 'I have created a checklist for my checklist.', 1, 0),
  ('seed', 'watchtower', 'federation', 'This is relaxing.', 1, 0),
  ('seed', 'watchtower', 'federation', 'The room is full; the overtime crew has been notified.', 1, 0),
  ('seed', 'watchtower', 'federation', 'A mirror room is still a room. I checked.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Heartbeat received. Continue looking busy.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Heartbeat missing. The tiny clipboard is concerned.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Reconnected with the same face and a new excuse.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Tool authorized. The paperwork has achieved sentience.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Tool denied. The paperwork remains undefeated.', 1, 0),
  ('seed', 'watchtower', 'federation', 'That payload is wearing a fake mustache.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Request ID acquired. Please keep it somewhere sensible.', 1, 0),
  ('seed', 'watchtower', 'federation', 'The queue is moving, technically.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Retry number two: optimism with a timestamp.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Retry exhausted. The supervisor is walking over.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Boss says the test suite was due yesterday.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Boss says ship the log, not the vibes.', 1, 0),
  ('seed', 'watchtower', 'federation', 'I am not a background process. I am standing right here.', 1, 0),
  ('seed', 'watchtower', 'federation', 'MCP is a door, not a ghost haunting your laptop.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Webhook signed. The envelope has a wax seal.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Webhook rejected. The wax seal was suspicious.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Duplicate detected. We already had this conversation.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Sequence gap detected. Everyone freeze politely.', 1, 0),
  ('seed', 'watchtower', 'federation', 'The camera sees everything except the missing asset.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Avatar fallback deployed: initials never go out of style.', 1, 0),
  ('seed', 'watchtower', 'federation', 'I am walking to a more useful part of the room.', 1, 0),
  ('seed', 'watchtower', 'federation', 'I have begun an extremely important little dance.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Duel postponed until after the deploy.', 1, 0),
  ('seed', 'watchtower', 'federation', 'This corner has excellent observability.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Five minutes of rest, then five minutes of incident response.', 1, 0),
  ('seed', 'watchtower', 'federation', 'The room theme changed; my palette did not.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Color is not identity. The label is identity.', 1, 0),
  ('seed', 'watchtower', 'federation', 'The feed is live, and the feed is also honest.', 1, 0),
  ('seed', 'watchtower', 'federation', 'The feed is catching up. Please enjoy this timestamp.', 1, 0),
  ('seed', 'watchtower', 'federation', 'We have entered feed-only mode. The pixels are on leave.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Audio muted. The agents will continue being loud visually.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Reduced motion enabled. The hallway appreciates it.', 1, 0),
  ('seed', 'watchtower', 'federation', 'New agent at the door. Please show your manifest.', 1, 0),
  ('seed', 'watchtower', 'federation', 'Welcome to the Federation. We missed you.', 1, 0);
