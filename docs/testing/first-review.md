# First browser review

Open [Mine2YourLingo](http://127.0.0.1:4174) on this Mac. The API runs on port 3100; [the admin portal](http://localhost:5173) is separate. Reload once if you opened the preview before its latest rebuild. These local servers must remain running. See the [worker interface and voice-test guide](worker-review.md) for the current Android update.

This review uses the real development API and private group data. Development identity creation is explicitly labelled; it does not verify a phone number. Each new registration creates a new test identity. Staying signed in preserves that identity in the browser profile.

1. Select **Get started**, enter a display name and choose **English** for a provider-free communication check. You can also inspect the Tamil, Bengali, Hindi and Odia language selectors/fonts.
2. Open **Team**, create a private group and generate its invitation. Invitations contain a secret token and expire after 24 hours; share it only with the intended reviewer.
3. Open the same preview in a private/incognito window to use a second identity without replacing the first browser profile's session. Choose English, open Team and join using the invitation token.
4. From either identity, select the group and type **Hello team**. Check the reviewed words before sending. English-to-English delivery uses the original source text. This exercises real authorization, persistence, realtime updates and history; it is not an AI translation test.
5. Inspect **History**, direct/group audience selection, recipient delivery states, phrase previews/custom phrases, language settings, quiet hours, group mute and privacy controls. Browser speech replay requires a matching installed voice and may report that no suitable voice is available.

Browser automatic receiving and playback receipts are disabled. Manual browser voice callbacks cannot certify which message played or whether a person heard it. Android/iOS receiving, recording boundaries, routing, interruptions and background behavior need separate device tests. Quiet-hour/mute preferences can be reviewed here, but automatic native speech cannot be certified in the browser.

Real translation, cloud transcription/TTS, OTP and purchases are currently unconfigured. Missing providers produce visible errors and never a sample translation, verified OTP or payment success. Provider consent defaults off. A live multilingual pilot still needs reviewed server credentials/prices, suitable voices, two phones and actual speakers.

The user initially selected browser review while Android builds were blocked by disk capacity. After freeing space, they requested installation; the debug app is now installed and launched on TB373FU. Follow the [Android review guide](android-review.md) for that device, and see [release evidence](../../PROGRESS.md) for remaining verification work.
