# QA: In-app event creation and navigation

**Feature:** a **+** button in the NavCal top bar opens the iOS new-event editor. Saving closes the editor, and the new event appears in today's list right away. Its Waze, Google Maps and Apple Maps buttons work like those on any other event.

Record results in the **Actual** column of section 3. The **Automated** column shows steps that `EventCreationUITests` and `EventCreationTests` also cover. Manual testing is still needed on a real device with Waze and Google Maps installed.

---

## 1. Prerequisites and environment setup

### Build
- Xcode 16 or later. Open `NavCal.xcodeproj`, select the **NavCal** scheme, and run the Debug configuration.
- **Remove `-NavCalDemo`** from *Edit Scheme → Run → Arguments* if it's there. Demo mode shows fixed sample events and hides the **+** button.

### Devices

| Device | Purpose |
|---|---|
| iOS Simulator, iOS 17 or later | Creating events, auto-refresh, web fallbacks (Waze and Google Maps aren't installed) |
| Physical iPhone with **Waze** and **Google Maps** installed | Opening the native apps |
| Physical iPhone **without** Waze or Google Maps (optional) | Web fallback on a real device |

### Calendar permission states to test

| State | How to set it |
|---|---|
| Not determined (fresh install) | Delete NavCal from the device, then reinstall. Simulator: `xcrun simctl privacy booted reset calendar com.navcal.NavCal` |
| Full access | Tap **Allow Full Access** at the prompt. Simulator shortcut: `xcrun simctl privacy booted grant calendar com.navcal.NavCal` |
| Denied | Settings → Privacy & Security → Calendars → NavCal → **None** |

### Starting state
- The device has at least one writable calendar. The simulator's default "Calendar" is fine. To check on a real device, open Apple's Calendar app, tap **Calendars**, and look for a calendar you can add events to (iCloud, Gmail, "On My iPhone", etc.). Holidays, Birthdays and subscribed calendars are read-only and don't count. Section G tests the case with no writable calendar.
- Note the current time. The editor's default start time is the next full hour, so for the event to count as "today", run the test before 11:00 PM or change the date manually.
- Location permission is optional for this feature (it only affects the weather header).

---

## 2. Step-by-step execution

### A. Permissions and button visibility
1. Fresh install, then launch NavCal. **Allow Full Access** to calendars.
2. Look at the top-right of the top bar.
3. Deny calendar access (see above), return to NavCal, and pull to refresh or relaunch.
4. Restore full access and relaunch.

### B. Create an event with a street address
5. Tap **+**.
6. Check the editor's default values: title is empty, calendar is the default, start is the next full hour, end is one hour later.
7. Enter **Title** `Merch visit` and **Location** `1 Infinite Loop, Cupertino, CA 95014`. Leave the times as they are.
8. Tap **Add** (called **Done** on iOS 26 and later).
9. Without pulling to refresh, check the new card.

### C. Create an event whose store is only in the title
10. Tap **+**. Enter **Title** `Reset – Safeway 555` and leave **Location** blank. Tap **Add** or **Done**.
11. Check the new card.

### D. Cancel and discard
12. Tap **+**, type a title, and tap **Cancel**. If iOS asks, confirm **Discard Changes**.
13. Check the list.
14. Tap **+** and swipe the editor down without saving.

### E. Navigation from newly created events
Do these on the card from step 7 (**B**) and the card from step 10 (**C**).

15. Tap **Waze**.
16. Return to NavCal and tap **Google**.
17. Return to NavCal and tap **Maps**.
18. Real device without Waze or Google Maps: repeat steps 15–16.

### F. Edge cases
19. Create an event with **Location** `Fred Meyer #658 & Co, 3805 SE Hawthorne Blvd, Portland, OR` and tap **Google**.
20. Create an event titled `Team call` with no location.
21. Create an event for **tomorrow**.
22. Create an all-day event for today.
23. With NavCal open, add an event in the Calendar app, then switch back to NavCal.
24. Swipe left on the event list. Tap **Today**. Then swipe right.
25. Swipe to tomorrow and tap **+**.

### G. No writable calendar (real device)
Set up a phone whose only synced account has Calendars off. For example, keep only a Gmail account and turn off **Settings → Apps → Calendar → Calendar Accounts → Gmail → Calendars**, with iCloud Calendars off.

26. Tap **+**.
27. Turn that account's **Calendars** back on, wait until its calendars appear in Apple's Calendar app, return to NavCal, and tap **+**.

---

## 3. Expected vs. actual results

| # | Step | Expected | Actual | Automated |
|---|---|---|---|---|
| 1 | Fresh install | iOS asks for calendar access. After **Allow**, today's events load (or "Nothing Scheduled"). | | — |
| 2 | Toolbar | **+** is shown top-right. VoiceOver reads "New Event". | | UI test |
| 3 | Access denied | **+** is hidden. "Calendar Access Needed" appears with an **Open Settings** button. | | — |
| 4 | Access restored | **+** reappears. | | — |
| 5 | Tap **+** | The system new-event editor opens as a sheet. | | UI test |
| 6 | Defaults | Default calendar selected. Start is the next full hour, end one hour later. | | Unit test (`draftEventStartsAtNextFullHourForOneHour`); dates also seen in the UI test's view dump |
| 8 | Save | The editor closes. | | UI test |
| 9 | New card (address) | Appears right away with no pull to refresh, in time order. Shows the title, time range and address. No "Detected from event title" label. All three buttons enabled. | | UI test (appearance); unit test (address mapping) |
| 11 | New card (store in title) | Location reads **Safeway 555** with "Detected from event title". Buttons enabled. | | UI test (with a random store number) |
| 13 | Cancel | The editor closes. No new card, and the list doesn't jump. | | Unit test (`savingReloadsScheduleButCancelingDoesNot`) |
| 14 | Swipe down | The sheet closes and nothing is saved. You can tap **+** again right away. | | — |
| 15 | Waze (device, installed) | Waze opens and starts navigating to the address or to "Safeway 555". | | — |
| 15 | Waze (simulator or not installed) | Safari opens `https://waze.com/ul?q=…&navigate=yes`. | | UI test (Safari opens) |
| 16 | Google (installed) | Google Maps opens with driving directions to the destination. | | Unit test (URL) |
| 16 | Google (not installed) | Safari opens `https://www.google.com/maps/dir/?api=1&destination=…`. | | Unit test (fallback logic) |
| 17 | Maps | Apple Maps opens with driving directions to the destination. | | Unit test (URL) |
| 19 | Special characters | The full address arrives intact in Google Maps, and `#` and `&` don't cut it short. | | Unit test (`encodesReservedCharacters`) |
| 20 | No location | Card shows "No location" and all three buttons are greyed out and don't respond. | | — |
| 21 | Tomorrow | Saves without error. No card appears on today's page. Swipe left: the event is listed on tomorrow's page. | | UI test (swiping); unit test (day loading) |
| 22 | All-day | Card appears **after** the timed events with "All day". | | — |
| 23 | External change | The new event appears when you return to NavCal. | | — |
| 24 | Day swiping | Swipe left: the title changes to tomorrow's date (e.g. "Friday, Sep 25"), the weather disappears, and **Today** appears top-left. **Today**: returns to today's page. Swipe right: yesterday, with finished events marked DONE. | | UI test |
| 26 | No writable calendar | Instead of the editor flashing open and closing, a **"No Calendar to Save To"** alert names the account with Calendars off (e.g. "Gmail") and gives the Settings path. **Create NavCal Calendar** appears only if the phone has an iCloud or "On My iPhone" account. | | Unit test (alert message) |
| 27 | Calendars turned back on | Without relaunching NavCal, **+** opens the editor and it stays open. Saving adds the event to that account's calendar. | | — |
| 25 | + on another day | The editor's start time defaults to 9:00 AM on that day. After saving, the event appears on that page. | | Unit test (`draftEventForAnotherDayStartsAt9AM`) |

### Reporting a failure
Include the device model, iOS version, NavCal build, calendar permission state, the step number, a screen recording, and whether Waze or Google Maps is installed.

### Clean-up
Delete the test events in the Calendar app. The UI test leaves `Reset Safeway ###` events in the simulator's calendar each time it runs.
