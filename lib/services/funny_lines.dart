// lib/services/funny_lines.dart — user-written reveal jokes, verbatim.
// Five per score tier; the host picks one per attempt and ships it in the
// score echo so every phone laughs at the same line. English arrays are
// direct translations of the originals (user-reviewed); the host's language
// chooses which array ships.
import 'dart:math';

import '../state/language.dart';

class FunnyLines {
  static final _random = Random();

  // < 20%: كارثة صوتية
  static const List<String> tier1 = [
    "المايك استقال من وراك 💔",
    "صوتك بجيب الجلطة والله!",
    "المايك صار يطلب رحمة والله 🏳️",
    "هاد تقليد ولا نداء استغاثة؟",
    "حتى الموبايل خجل من هذا الصوت 🤦‍♂️",
  ];

  // < 40%: محاولة معوقة
  static const List<String> tier2 = [
    "عم تشلف من عندك تشليف 🌚",
    "تشابه أسماء فقط لا غير 😅",
    "بدك دورة تقوية بالتقليد ضروري",
    "الصوت طالع من تحت السجادة",
    "محاولة بتشكر عليها.. بس لا تعيدها",
  ];

  // < 60%: ماشية أمورها
  static const List<String> tier3 = [
    "يلا ماشي حالها.. فيها روح 🤙",
    "مشّيها.. الجود من الموجود 🤷‍♂️️",
    "قريبة شوي، بدها بس شوية رتوش",
    "مشي حالك.. أهون من غيرك",
    "في أمل منك.. لا تستسلم!",
  ];

  // < 80%: أداء قوي وحلو
  static const List<String> tier4 = [
    "يا عيني! الحنجرة شغال صح اليوم 🎶",
    "والله ظابطة! حنجرة ذهبية",
    "قريبة كتير.. ناقصها تنتين بس 🎯",
    "معلم! التقليد طلع عالمسطرة",
    "خطير! أدائك اليوم حريقة 🔥",
  ];

  // 80% - 100%: أسطوري / طبق الأصل
  static const List<String> tier5 = [
    "نسخة طبق الأصل! منين سارق الصوت؟ 😱",
    "يا زلمة أنت الأسطورة تبع اللعبة!",
    "طابش الجو.. جابها ع السانتي تماماً 🔥",
    "مستحيل! هاد الصوت الأصلي مو تقليد 👑",
    "يا عيني عليك! أكلت الجو كله 🔥",
  ];

  // English translations of the same jokes, index-matched.
  static const List<String> tier1En = [
    "Your mic just resigned because of you 💔",
    "By God, your voice belongs in a cardiology ward!",
    "The mic started begging for mercy 🏳️",
    "Is that a mimic or a distress call?",
    "Even the phone is ashamed of that sound 🤦‍♂️",
  ];

  static const List<String> tier2En = [
    "You're mumbling gibberish from home 🌚",
    "Resemblance in name only, nothing more 😅",
    "You badly need a mimic refresher course",
    "That sound came from under the rug",
    "One to send a thank-you note for… just don't repeat it",
  ];

  static const List<String> tier3En = [
    "It kinda walks fine… it's alive 🤙",
    "It'll do… best of what's available 🤷‍♂️️",
    "Close-ish — only needs a few touch-ups",
    "It passes… better than nothing without you",
    "There's hope for you… don't give up!",
  ];

  static const List<String> tier4En = [
    "Look at you! The throat actually works today 🎶",
    "Honestly nailed it! Golden throat",
    "So close… it only needed a sting 🎯",
    "Maestro! The mimic came out flawless",
    "Dangerous! Your performance today is on fire 🔥",
  ];

  static const List<String> tier5En = [
    "An exact copy! Where'd you steal the sound from? 😱",
    "My man, you ARE the game's legend!",
    "You shut the place down… wrapped it up perfectly 🔥",
    "Impossible! That's the original, not a mimic 👑",
    "Oh my! You devoured the whole vibe 🔥",
  ];

  static String pickFor(double score) {
    final List<String> tier;
    switch (currentLanguage) {
      case AppLanguage.arabic:
        tier = score < 20
            ? tier1
            : score < 40
                ? tier2
                : score < 60
                    ? tier3
                    : score < 80
                        ? tier4
                        : tier5;
      case AppLanguage.english:
        tier = score < 20
            ? tier1En
            : score < 40
                ? tier2En
                : score < 60
                    ? tier3En
                    : score < 80
                        ? tier4En
                        : tier5En;
    }
    return tier[_random.nextInt(tier.length)];
  }
}
