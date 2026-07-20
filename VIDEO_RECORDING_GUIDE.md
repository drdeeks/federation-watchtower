# 🎬 Easy Video Recording Guide

**For OpenAI Build Week - Federation Watchtower Demo**

---

## ⏱️ Total Time: 3 minutes max

## 📹 Recording Tools (Pick One)

| Tool | Platform | Ease | Link |
| --- | --- | --- | --- |
| **Loom** | All | ⭐⭐⭐⭐⭐ | https://loom.com (free tier) |
| **OBS Studio** | All | ⭐⭐⭐⭐ | https://obsproject.com (free) |
| **Windows Game Bar** | Windows | ⭐⭐⭐⭐⭐ | Win + Alt + R |
| **QuickTime** | Mac | ⭐⭐⭐⭐⭐ | Cmd + Shift + 5 |
| **SimpleScreenRecorder** | Linux | ⭐⭐⭐⭐ | `sudo apt install simplescreenrecorder` |

**Recommendation: Use Loom** - it's the easiest, records screen + audio, and uploads directly to the cloud.

---

## 🎯 Step-by-Step Recording Script

### Before You Start Recording

1. **Open these 3 browser tabs:**
   - Tab 1: https://watch.drdeeks.xyz/ (Watchtower)
   - Tab 2: https://federation.drdeeks.xyz/onboarding.html (Onboarding)
   - Tab 3: https://github.com/YOUR_USERNAME/federation (Your repo)

2. **Test your microphone** - do a 5-second test recording first

3. **Close unnecessary tabs/apps** - reduce distractions

---

### Recording Steps

#### 1. Introduction (10 seconds)
**Navigate to:** Watchtower (Tab 1)

**Say:** *"Hi, I'm [your name]. This is Federation Watchtower - a developer tool that makes autonomous agent work visible before it becomes expensive."*

**Show:** The main Watchtower page with the camera view, agent roster, and event feed.

---

#### 2. The Problem (15 seconds)
**Say:** *"While building with autonomous agents, I spent 25,000 credits with no visibility into what was running, failing, or costing money. Normal logs are hard to monitor during fast multi-agent builds."*

**Show:** Still on Watchtower page, point to the event feed.

---

#### 3. Live Demo - Create Agent (45 seconds)
**Navigate to:** Onboarding (Tab 2)

**Say:** *"Let me show you how it works. First, I create an owner credential..."*

**Do:**
1. Click **"Create owner"**
2. Fill in:
   - Owner ID: `demo-judge`
   - Display name: `Demo Judge`
   - Owner type: `individual`
3. Click **"Create owner"**
4. **Show the credential popup** - say: *"This is a scoped owner credential - never shared"*

**Say:** *"Now I register an agent with a stable identity..."*

**Do:**
1. Scroll to **"Register an agent"**
2. Fill in:
   - Agent ID: `judge-demo-1`
   - Display name: `Judge Demo Agent`
   - Project ID: `demo-project`
   - Role: `testing`
   - Capabilities: `test,report`
   - Palette: `build`
   - Character: `runner`
3. ✅ Check **"Show this agent on public Watchtower"**
4. Click **"Register agent"**
5. **Show the agent credential** - say: *"This scoped credential goes to the agent host"*

---

#### 4. Live Demo - Run Loop (60 seconds)
**Stay on:** Onboarding page (Tab 2)

**Say:** *"Now I run the live loop - connect, heartbeat, emit events, disconnect..."*

**Do:**
1. Click **"Connect"** - watch the log
   - Say: *"Connect establishes the session"*
2. Click **"Heartbeat"**
   - Say: *"Heartbeat arms the watchdog deadline"*
3. Pick event type: `run.started`
4. Click **"Emit action now"**
   - Say: *"This emits a real operational event"*
5. Click **"Start auto loop"**
   - Say: *"Auto loop heartbeats and emits every 30 seconds"*
   - Wait 10 seconds watching the log
6. Click **"Stop auto loop"**
7. Click **"Disconnect"**
   - Say: *"Disconnect marks the agent offline"*

---

#### 5. Show on Watchtower (30 seconds)
**Navigate to:** Watchtower (Tab 1)

**Say:** *"Now let's see it on the public Watchtower..."*

**Do:**
1. Your agent should appear in the roster (right side)
2. **Click on your agent** in the roster
3. **Show the agent detail popup:**
   - Owner label
   - Role: testing
   - Status: connected/offline
   - Room assignment
   - Capabilities
4. **Show the event feed** (bottom)
   - Say: *"You can see the real events my agent just emitted"*

---

#### 6. Show Admin Console (30 seconds)
**Navigate to:** Manage (https://federation.drdeeks.xyz/manage.html)

**Say:** *"For operators, there's an admin console..."*

**Do:**
1. Show the connection screen (or connect if you have admin token)
2. **Say:** *"Admins can pause, resume, or revoke agents"*
3. **Point to:** Agent table with columns: Agent, Project, Room, Status, Actions
4. **Say:** *"Revoke invalidates credentials but preserves event history"*
5. If connected, show the **"Alert webhook"** section at bottom
   - Say: *"Alert deliveries are provable - signed and receipted"*

---

#### 7. Explain Codex Usage (20 seconds)
**Navigate to:** GitHub README (Tab 3)

**Say:** *"I built this with Codex during OpenAI Build Week..."*

**Do:**
1. Scroll to **"How Codex accelerated the work"** table
2. **Point to the table** while saying:
   - *"Codex helped consolidate the repository"*
   - *"Wire and test Worker surfaces"*
   - *"Build the camera-style Watchtower UI"*
   - *"Document the operational lifecycle"*

---

#### 8. Wrap Up (10 seconds)
**Navigate to:** Back to Watchtower (Tab 1)

**Say:** *"Federation Watchtower makes autonomous work visible before it becomes expensive. Built with Codex for OpenAI Build Week. Thanks for watching!"*

**Stop recording**

---

## ✅ After Recording

1. **Upload to YouTube**
   - Set visibility to **Public** or **Unlisted**
   - Title: `Federation Watchtower - OpenAI Build Week Demo`
   - Description: Include link to repo and live demo

2. **Copy the YouTube URL** - you'll add this to Devpost

3. **Get your /feedback session ID** from Codex
   - Open Codex
   - Find the session where you built the core functionality
   - Copy the session ID from the URL or share link

4. **Complete Devpost submission:**
   - Add YouTube URL
   - Add /feedback session ID
   - Answer required fields (submitter type, residence, category)
   - **Attach project to OpenAI Build Week challenge**
   - Press **Submit**

---

## 🎤 Tips for a Great Video

### Do:
- ✅ Speak clearly and at a moderate pace
- ✅ Use a quiet room with minimal background noise
- ✅ Keep the demo focused - stick to the script
- ✅ Show the actual working system (not slides)
- ✅ Point to important UI elements as you mention them
- ✅ Keep it under 3 minutes (judges won't watch beyond 3 min)

### Don't:
- ❌ Include copyrighted music or third-party trademarks
- ❌ Go off on tangents or show unrelated features
- ❌ Rush through the demo - judges need to see it working
- ❌ Use technical jargon without explaining it
- ❌ Exceed 3 minutes

---

## 🆘 Troubleshooting

### "My agent doesn't appear on Watchtower"
- Make sure you checked **"Show this agent on public Watchtower"** when registering
- Wait 5-10 seconds after emitting events
- Refresh the Watchtower page

### "The onboarding page shows an error"
- Check browser console for errors (F12)
- Try a different browser
- The live system may be temporarily unavailable

### "I can't access the admin console"
- The admin console requires the `WATCHTOWER_ADMIN_TOKEN`
- It's OK to just show the connection screen and explain what it does
- Judges understand not all features are publicly accessible

### "My microphone isn't working"
- Test audio before starting the main recording
- Check system audio settings
- Try a different recording tool (Loom is most reliable)

---

## 📋 Checklist

- [ ] Recording tool installed and tested
- [ ] Three browser tabs open (Watchtower, Onboarding, GitHub)
- [ ] Microphone tested and working
- [ ] Followed the 8-step recording script
- [ ] Video is under 3 minutes
- [ ] Uploaded to YouTube (public or unlisted)
- [ ] Got /feedback session ID from Codex
- [ ] Added YouTube URL to Devpost
- [ ] Added session ID to Devpost
- [ ] Answered all required Devpost fields
- [ ] Attached project to OpenAI Build Week challenge
- [ ] Pressed Submit button

**Deadline: July 21, 2026 @ 5:00pm PDT**

---

**Good luck! You've built something amazing - now show it off! 🚀**
