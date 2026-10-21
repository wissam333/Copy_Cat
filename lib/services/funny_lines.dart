// lib/services/funny_lines.dart — user-written reveal jokes, verbatim.
// Five per score tier; the host picks one per attempt and ships it in the
// score echo so every phone laughs at the same line.
import 'dart:math';

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

  static String pickFor(double score) {
    final tier = score < 20
        ? tier1
        : score < 40
            ? tier2
            : score < 60
                ? tier3
                : score < 80
                    ? tier4
                    : tier5;
    return tier[_random.nextInt(tier.length)];
  }
}
