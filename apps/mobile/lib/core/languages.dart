class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final String locale;
  const AppLanguage(this.code, this.name, this.nativeName, this.locale);
  static const defaults = {'ta', 'bn', 'hi', 'or', 'en'};
  static const all = [
    AppLanguage('ta', 'Tamil', 'தமிழ்', 'ta-IN'),
    AppLanguage('bn', 'Bengali', 'বাংলা', 'bn-IN'),
    AppLanguage('hi', 'Hindi', 'हिन्दी', 'hi-IN'),
    AppLanguage('or', 'Odia', 'ଓଡ଼ିଆ', 'or-IN'),
    AppLanguage('en', 'English', 'English', 'en-IN'),
    AppLanguage('te', 'Telugu', 'తెలుగు', 'te-IN'),
    AppLanguage('kn', 'Kannada', 'ಕನ್ನಡ', 'kn-IN'),
    AppLanguage('ml', 'Malayalam', 'മലയാളം', 'ml-IN'),
    AppLanguage('mr', 'Marathi', 'मराठी', 'mr-IN'),
    AppLanguage('gu', 'Gujarati', 'ગુજરાતી', 'gu-IN'),
    AppLanguage('pa', 'Punjabi', 'ਪੰਜਾਬੀ', 'pa-IN'),
    AppLanguage('ur', 'Urdu', 'اردو', 'ur-IN'),
    AppLanguage('as', 'Assamese', 'অসমীয়া', 'as-IN'),
    AppLanguage('brx', 'Bodo', 'बड़ो', 'brx-IN'),
    AppLanguage('doi', 'Dogri', 'डोगरी', 'doi-IN'),
    AppLanguage('ks', 'Kashmiri', 'کٲشُر', 'ks-IN'),
    AppLanguage('kok', 'Konkani', 'कोंकणी', 'kok-IN'),
    AppLanguage('mai', 'Maithili', 'मैथिली', 'mai-IN'),
    AppLanguage('mni', 'Manipuri', 'ꯃꯤꯇꯩꯂꯣꯟ', 'mni-IN'),
    AppLanguage('ne', 'Nepali', 'नेपाली', 'ne-IN'),
    AppLanguage('sa', 'Sanskrit', 'संस्कृतम्', 'sa-IN'),
    AppLanguage('sat', 'Santali', 'ᱥᱟᱱᱛᱟᱲᱤ', 'sat-IN'),
    AppLanguage('sd', 'Sindhi', 'سنڌي', 'sd-IN'),
  ];
  static AppLanguage of(String? code) =>
      all.firstWhere((l) => l.code == code, orElse: () => all[4]);
}

/// Small reviewed interface catalog. Untranslated interface labels use English.
class Labels {
  static const _catalog = {
    'ta': {
      'talkTitle': 'உங்கள் குழுவிடம் பேசுங்கள்',
      'talkHelp': 'குழுவைத் தேர்ந்தெடுத்து பேசுங்கள். சொற்களைச் சரிபார்த்து அனுப்புங்கள்.',
      'testVoice': 'இந்தக் கருவியில் குரலைச் சோதிக்கவும்',
      'testHelp': 'குழுவிற்கு எதுவும் அனுப்பப்படாது.',
      'listenSettings': 'கேட்பதற்கான அமைப்புகள்',
      'wait': 'காத்திருக்கவும்…',
      'stop': 'பதிவை நிறுத்தவும்',
      'reviewHelp':
          'நிறுத்த மீண்டும் தட்டவும். அனுப்புமுன் சொற்களைச் சரிபார்க்கவும்.',
      'type': 'தட்டச்சு செய்யவும்',
      'home': 'முகப்பு',
      'history': 'வரலாறு',
      'phrases': 'சொற்றொடர்கள்',
      'team': 'குழு',
      'speak': 'பேசத் தட்டவும்',
      'settings': 'அமைப்புகள்',
    },
    'bn': {
      'talkTitle': 'আপনার দলের সঙ্গে কথা বলুন',
      'talkHelp': 'দল বেছে নিন। বলুন, কথা যাচাই করুন, তারপর পাঠান।',
      'testVoice': 'এই ফোনে কণ্ঠ পরীক্ষা করুন',
      'testHelp': 'দলের কাছে কিছু পাঠানো হবে না।',
      'listenSettings': 'শোনার সেটিংস',
      'wait': 'অপেক্ষা করুন…',
      'stop': 'রেকর্ডিং বন্ধ করুন',
      'reviewHelp': 'বন্ধ করতে আবার চাপুন। পাঠানোর আগে কথা যাচাই করুন।',
      'type': 'লিখে পাঠান',
      'home': 'হোম',
      'history': 'ইতিহাস',
      'phrases': 'বাক্যাংশ',
      'team': 'দল',
      'speak': 'কথা বলতে চাপুন',
      'settings': 'সেটিংস',
    },
    'hi': {
      'talkTitle': 'अपनी टीम से बात करें',
      'talkHelp': 'टीम चुनें। बोलें, शब्द जाँचें, फिर भेजें।',
      'testVoice': 'इस फ़ोन पर आवाज़ जाँचें',
      'testHelp': 'टीम को कुछ नहीं भेजा जाएगा।',
      'listenSettings': 'सुनने की सेटिंग्स',
      'wait': 'कृपया रुकें…',
      'stop': 'रिकॉर्डिंग रोकें',
      'reviewHelp': 'रोकने के लिए फिर टैप करें। भेजने से पहले शब्द जाँचें।',
      'type': 'लिखकर भेजें',
      'home': 'होम',
      'history': 'इतिहास',
      'phrases': 'वाक्यांश',
      'team': 'टीम',
      'speak': 'बोलने के लिए टैप करें',
      'settings': 'सेटिंग्स',
    },
    'or': {
      'talkTitle': 'ଆପଣଙ୍କ ଦଳ ସହ କଥା ହୁଅନ୍ତୁ',
      'talkHelp': 'ଦଳ ବାଛନ୍ତୁ। କୁହନ୍ତୁ, ଶବ୍ଦ ଯାଞ୍ଚ କରନ୍ତୁ, ତାପରେ ପଠାନ୍ତୁ।',
      'testVoice': 'ଏହି ଫୋନରେ ସ୍ୱର ପରୀକ୍ଷା କରନ୍ତୁ',
      'testHelp': 'ଦଳକୁ କିଛି ପଠାଯିବ ନାହିଁ।',
      'listenSettings': 'ଶୁଣିବା ସେଟିଂସ୍',
      'wait': 'ଅପେକ୍ଷା କରନ୍ତୁ…',
      'stop': 'ରେକର୍ଡିଂ ବନ୍ଦ କରନ୍ତୁ',
      'reviewHelp':
          'ବନ୍ଦ କରିବାକୁ ପୁଣି ଟ୍ୟାପ୍ କରନ୍ତୁ। ପଠାଇବା ପୂର୍ବରୁ ଶବ୍ଦ ଯାଞ୍ଚ କରନ୍ତୁ।',
      'type': 'ଲେଖି ପଠାନ୍ତୁ',
      'home': 'ମୁଖ୍ୟ',
      'history': 'ଇତିହାସ',
      'phrases': 'ବାକ୍ୟାଂଶ',
      'team': 'ଦଳ',
      'speak': 'କହିବା ପାଇଁ ଟ୍ୟାପ୍ କରନ୍ତୁ',
      'settings': 'ସେଟିଂସ୍',
    },
    'en': {
      'talkTitle': 'Speak to your team',
      'talkHelp': 'Choose your team. Speak, check your words, then send.',
      'testVoice': 'Test voice on this phone',
      'testHelp': 'Nothing is sent to your team.',
      'listenSettings': 'Listening settings',
      'wait': 'Please wait…',
      'stop': 'Stop recording',
      'reviewHelp': 'Tap again to stop. Check your words before sending.',
      'type': 'Type instead',
      'home': 'Home',
      'history': 'History',
      'phrases': 'Phrases',
      'team': 'Team',
      'speak': 'Tap to speak',
      'settings': 'Settings',
    },
  };
  static String get(String code, String key) =>
      _catalog[code]?[key] ?? _catalog['en']?[key] ?? key;
}
