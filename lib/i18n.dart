// lib/i18n.dart — the app's translation helper. The looks up keys are the
// original Arabic UI strings themselves, so converting a screen is just
// wrapping literals with t(). Arabic prints the key untouched; English
// looks up [_en] and falls back to Arabic when a key has no entry yet, so
// screens can be converted gradually without anything breaking.
import 'state/language.dart';

const Map<String, String> _en = {
  'قلّد الصوت… واجمع النقاط!': "Mimic the sound… rake the points!",
  // home_screen
  'فردي (بدون شبكة)': 'Solo (no network)',
  'شفرة مقبولة! +{n} 🪙': 'Code accepted! +{n} 🪙',
  'استخدمت هذه الشفرة من قبل': 'You already used this code',
  'شفرة غير صالحة': 'Invalid code',
  'سجّل صوتًا من ٢–٦ ثوانٍ في أصواتي، ثم العب.':
      'Record a 2–6 second sound in My Sounds, then play.',
  'لديك {n} أصوات. اختر:': '{n} sounds ready — pick:',
  'اللعب بموبايل واحد': 'Play on one phone',
  'إنشاء غرفة': 'Host a room',
  'انضمام': 'Join',
  'أصواتي': 'My Sounds',
  'شخصيتك — اضغط للمتجر': 'Your character — tap for the shop',
  'رصيدك {n} 🪙': 'Balance {n} 🪙',
  'اسمك': 'Your name',
  'اسم الغرفة (للاستضافة)': 'Room name (for hosting)',
  'العب مع أصدقائك على نفس شبكة الواي فاي':
      'Play with friends on the same Wi-Fi network',
  'نسخة طبق الأصل!': 'A perfect copy!',
  'أسطورة التقليد': 'Mimic legend',
  'تقليد قوي': 'Strong mimic',
  'قريب نوعًا ما': 'Kinda close',
  'به شبه': 'A hint of resemblance',
  'بعيد… حاول الاقتراب أكثر': 'Way off… inch closer',
  'لم نلتقط صوتك': "We didn't catch your voice",
  'استعد! يبدأ التسجيل خلال…': 'Get set! Recording starts in…',
  'حفلة عشوائية': 'Random Party',
  'كل جولة صوت مفاجئ. الكل يقلّده بالدور، والنقاط تتراكم.':
      'Every round is a surprise sound. Take turns mimicking; points pile up.',
  'اختيار اللاعب': "Player's Choice",
  'واحد يختار الصوت. الباقي يقلّدون قبله، وهو يلعب آخر واحد.':
      'One player picks the sound. Everyone mimics it before them; they go last.',
  'تحدي المضيف': 'Host Challenge',
  'تختار قائمة الأصوات. الكل يقلّد كل صوت قبل الانتقال للي بعده.':
      'You pick the sound list. Everyone mimics each sound before the turn moves on.',
  '{n} نقطة': '{n} points',
  'صوت بنغمة — اللحن هو الحكم': 'Pitched sound — melody is the judge',
  'كلام — وضوح النطق هو الحكم': 'Speech — articulation clarity is the judge',
  'بلا نغمة — النوع والإيقاع هما الحكم':
      'No pitch — timbre and rhythm are the judges',
  'اللحن': 'Melody',
  'الإيقاع': 'Rhythm',
  'النبرة': 'Timbre',
  'الطاقة': 'Energy',
  'وضوح النطق': 'Clarity',
  'لحن الكلام': 'Speech Tune',
  'نوع الصوت': 'Timbre Match',
  'المكتبة فارغة.': 'The library is empty.',
  '{n} ثانية': '{n}s',
  // results_screen
  'نهاية الحفلة': "Party's Over",
  'لا نتائج بعد.': 'No results yet.',
  'الفائز: {n}': 'Winner: {n}',
  'تعادل: {n}': 'Tie: {n}',
  'و': ' & ',
  'الترتيب': 'Standings',
  'عملاتك تفتح شخصيات المتجر — بالتوفيق':
      'Your coins unlock shop characters — good luck',
  'الجولات': 'Rounds',
  'الجولة {n}': 'Round {n}',
  'الجولة {n} · {title}': 'Round {n} · {title}',
  'نفس الحفلة': 'Same party again',
  'انتظر حتى يبدأ المضيف حفلة جديدة':
      'Wait for the host to start a new party',
  'الرئيسية': 'Home',
  'لا نتائج بعد — العب دورًا أولًا.': 'No results yet — play a round first.',
  'تشغيل أفضل محاولة': 'Play the best attempt',
  'فشل التشغيل: {n}': 'Playback failed: {n}',
  'لا يوجد.': 'None.',
  'العب مجددًا': 'Play again',
  // shop_screen + shop_catalog data names
  'المتجر': 'The Shop',
  'شخصيات': 'Characters',
  'إيموجي': 'Emoji',
  'قوى': 'Power-ups',
  'اسحب يمينًا فيدور الوجه مع إصبعك':
      'Drag your finger to spin the face',
  'شخصيتك الحالية': 'Currently equipped',
  'جهّز هذه الشخصية': 'Equip this character',
  'اشترِ بـ {n}': 'Buy for {n}',
  'ينقصك {n} — العب لتجمع': 'Short {n} — play to earn',
  'أصبحت {n} لك! جهّزها لتظهر في الحفلة':
      '{n} is yours! Equip it to show it in the party',
  'عملاتك لا تكفي — العب واجمع المزيد':
      'Not enough coins — play and earn more',
  'لا يوجد إيموجي مجاني هنا. كل إرسال أثناء انتظار دور غيرك يسحب من رصيدك فورًا — الأوقح أغلى.':
      "No free emoji here. Every send while waiting for your turn pulls from your balance instantly — the rudest cost the most.",
  '🪙 {n} لكل إرسال': '🪙 {n} per send',
  'قوى تُستخدم مرة واحدة أثناء الحفلة. الشراء يضيف للمخزون، وكل استخدام يستهلك وحدة — الحكم على التوقيت هو المضيف، والاستخدام الخاطئ لا يُسترَد.':
      'One-shot power-ups for mid-party. Buying adds to the stock, every use burns one — the host decides timing, failed uses are not refunded.',
  'المخزون: {n}': 'Stock: {n}',
  'وحدة {n} في مخزونك — استخدمها أثناء الحفلة':
      'One {n} added to your stock — use it during the party',
  'مجهز': 'Equipped',
  'مجاني': 'Free',
  'شاب عادي': 'Regular Guy',
  'بنت عادية': 'Regular Girl',
  'طباخ': 'Chef',
  'قزم': 'Elf',
  'نينجا': 'Ninja',
  'زومبي': 'Zombie',
  'غول': 'Ogre',
  'بقرة': 'Cow',
  'كلب': 'Dog',
  'قرصان': 'Pirate',
  'فايكنج': 'Viking',
  'ساحر': 'Wizard',
  'ساحرة': 'Witch',
  'مضاعفة': 'Double',
  'درع': 'Shield',
  'برق': 'Zap',
  'قبل دورك: تتضاعف نقطة هذه الجولة في المجموع':
      'Before your turn: this round lands double in your total',
  'أي وقت أثناء الحفلة: تُحذف أخفض جولة من مجموعك':
      'Anytime during the party: your worst round is dropped from the total',
  'أثناء انتظار دور غيرك: أجبره على إعادة التقليد مرة':
      'While waiting for someone else: force one redo of their take',
  // lobby_screen
  'نجمع أصوات الجميع ونخلطها، ونلعب حتى ٥ جولات مفاجئة.':
      'We gather everyone\'s sounds, shuffle them, and play up to 5 surprise rounds.',
  'كل لاعب يختار صوتًا مرة. الباقي يقلّدون أول، والمختار آخر واحد.':
      'Each player picks a sound once. Everyone else mimics it first; the picker goes last.',
  'المضيف يرتّب ١–٥ أصوات من مكتبته والكل يقلّدها بالترتيب.':
      'The host orders 1–5 sounds from their library; everyone mimics them in order.',
  'فشلت الاستضافة: {n}': 'Hosting failed: {n}',
  'جارٍ اكتشاف الغرف…': 'Scanning for rooms…',
  'فشل الاكتشاف: {n}': 'Discovery failed: {n}',
  'متصل بـ {n} — انتظر بدء المضيف للعبة':
      'Connected to {n} — wait for the host to start',
  'فشل الاتصال: {n}': 'Connecting failed: {n}',
  'غرفتك': 'Your Room',
  'الانضمام لغرفة': 'Join a Room',
  'الغرفة مقفلة — بدأت اللعبة': 'Room locked — game started',
  'بانتظار انضمام أصدقائك…': 'Waiting for friends to join…',
  '{n} هواتف في الغرفة': 'Phones in the room: {n}',
  'الهواتف في الغرفة': 'Phones in the room',
  'لا أحد بعد.': 'Nobody yet.',
  ' (مضيف)': ' (Host)',
  'هذا أنت': "That's you",
  'متصل': 'Connected',
  'طريقة اللعب': 'Game Mode',
  'أصوات التحدي (١–٥ بالترتيب)': 'Challenge sounds (1–5, in order)',
  'خمس جولات كافية': 'Five rounds is plenty',
  'غرف قريبة': 'Nearby Rooms',
  'ننتظر هاتفًا آخر… (اللعب بموبايل واحد من الرئيسية)':
      'Waiting for another phone… (one-phone play is on the home page)',
  'اختر صوتًا أولًا': 'Pick a sound first',
  'ابدأ اللعب': 'Start Playing',
  'غادر الغرفة': 'Leave Room',
  'لا توجد غرف بعد — تأكدوا من الاتصال بنفس شبكة الواي فاي.':
      "No rooms yet — make sure everyone is on the same Wi-Fi network.",
  'انضم': 'Join',
  'لديك عنوان IP المضيف؟': 'Have the host\'s IP address?',
  'يُستخدم غالبًا مع نقطة الاتصال': 'Typical with an LTE hotspot',
  'اتصال': 'Connect',
  // library_screen
  'تمت الإضافة: "{n}"': 'Added: "{n}"',
  'فشل الاستيراد: {n}': 'Import failed: {n}',
  'يلزم إذن الميكروفون': 'Microphone permission is required',
  'جارٍ التسجيل… غنِّ أو قلّد لمدة {n} ثوانٍ':
      'Recording… hum or mimic for {n} seconds',
  'التسجيل لم يُنتج ملفًا': 'Recording produced no file',
  'مقطع {h}:{m}': 'Clip {h}:{m}',
  'فشل التسجيل: {n}': 'Recording failed: {n}',
  'مكتبة الأصوات': 'Sound Library',
  'استيراد (2–6 ثوانٍ)': 'Import (2–6 seconds)',
  'جارٍ التسجيل…': 'Recording…',
  'تسجيل {n} ث': 'Record {n}s',
  'المدة': 'Length',
  'تحميل أصوات من الإنترنت': 'Download sounds from the internet',
  'أصوات التحدي': 'Challenge Sounds',
  'فارغة. استورد أو سجّل صوتًا من 2–6 ثوانٍ للّعب.':
      "Empty. Import or record a 2–6 second sound to play.",
  '{n} ث · {s} عينة نغمية': '{n}s · {s} pitch samples',
  // state/services strings
  'غرفة التقليد': 'The Mimic Room',
  'يستضيف "{n}" — الغرفة مقفلة':
      'Hosting "{n}" — room locked',
  'انضممت إلى الغرفة — بدأت اللعبة (مقفلة)':
      'Joined the room — game started (locked)',
  'تحدي': 'Challenge',
  'لم يتم اختيار ملف': 'No file was picked',
  'تعذّر قراءة الملف الصوتي': 'Could not read the audio file',
  'يجب أن يكون الصوت 2–6 ثوانٍ (هذا {n} ث)':
      'The sound must be 2–6 seconds (this one is {n}s)',
  'هذا الصوت موجود في المكتبة مسبقًا':
      'This sound is already in the library',
  'تم رفض إذن الميكروفون': 'Microphone permission was denied',
  // turn_runner zero notes (keys rendered via turnNoteLabel callers)
  'لم يصل ملف التحدي إلى هاتفك':
      "The challenge file didn't reach your phone",
  'تعذّر تشغيل صوت التحدي': 'Could not play the challenge sound',
  'تعذّر التسجيل — تحقق من إذن الميكروفون':
      'Recording failed — check mic permission',
  'التسجيل فارغ — لم يُلتقط أي صوت':
      'The recording is empty — no sound was captured',
  'الصوت منخفض جدًا — قرّب الهاتف وتحدّث بصوت أعلى':
      'The sound is too quiet — hold the phone closer and speak louder',
  'خطأ غير متوقع أثناء الدور':
      'Unexpected error during the turn',
  // instant_sounds (download screen) + instant_catalog titles
  'الأحدث': 'Newest',
  'الرائج': 'Trending',
  'الأشهر': 'Most Popular',
  'تعذّر جلب القائمة': 'Could not load the list',
  'تعذّر البحث': 'Search failed',
  'تعذّر جلب التصنيف': 'Could not load the category',
  'تعذّر البحث الشامل': 'Broad search failed',
  'تعذّر الجلب': 'Could not load',
  'تعذّر جلب اللوحات ({n})': 'Could not load the boards ({n})',
  'تعذّر جلب الأصوات': 'Could not load the sounds',
  'صوت': 'Sound',
  'الرابط غير صحيح — الصق رابط mp3 مباشر':
      'Bad link — paste a direct mp3 URL',
  'يجب أن يكون الرابط لملف mp3 مباشر (ينتهي بـ .mp3)، وليس رابط صفحة':
      'The link must be a direct mp3 file (ending in .mp3), not a page link',
  'فشل التحميل ({n})': 'Download failed ({n})',
  'الملف كبير جدًا': 'The file is too large',
  // instant_catalog built-in meme names (keys rendered where titles show)
  'خلص حلو عن طيزنا': 'Wrap It Up, Sweetly',
  'قبضة البعبع': 'Booba Punch',
  'لا تتصل': 'Do Not Call',
  'ابراهيم ارحمني': 'Ibrahim, Have Mercy',
  'راب زيج': 'Zajal Rap',
  'اكلنا خرا': "We're Screwed",
  'تتمنيك علي؟': 'You Wish It Was You?',
  'تلعب بوبجي 1': 'Playing PUBG 1',
  'بهجت صابر استاذ لغة عربية': 'Bahgat Saber, Arabic Teacher',
  'خلص': 'Khlas! (Enough)',
  'زيج عراقي اصيل': 'Authentic Iraqi Zajal',
  'استخدم قبضة البعبع': 'Use the Booba Punch',
  'سافل تبا لك ياصعلوك': 'Down, You Scoundrel!',
  'حياتي بقيت اجمل بكثير': 'My Life Got Much Prettier',
  'قطراف راسك': 'Twist Your Head',
  // download_screen
  'الكل': 'All',
  'إنستنتس': 'Instants',
  'ميم': 'Meme',
  '١٠١': '101',
  'لا لوحات — جرّب تصنيفًا ثانيًا': 'No boards — try another tag',
  'تعذّر جلب اللوحات': 'Could not load the boards',
  'اكتب كلمة للبحث': 'Type a word to search',
  'لا نتائج — جرّب كلمة ثانية': 'No results — try another word',
  'تعذّر الاتصال — هذه قائمة محفوظة':
      'Connection failed — this is a saved list',
  'تعذّر جلب المزيد': 'Could not load more',
  'اكتب رقم صفحة 1 أو أكثر': 'Type a page number of 1 or more',
  '▶ معاينة، ⬇ إضافة': '▶ preview, ⬇ add',
  'قائمة محفوظة ({n})': 'Saved list ({n})',
  'لوحات ١٠١': '101 Boards',
  'صفحة {n}': 'page {n}',
  'ميم:': 'Meme:',
  'كلها 2–6 ثوانٍ': "all 2–6 seconds",
  'فشل التحميل: {n}': 'Download failed: {n}',
  'تمت الإضافة للمكتبة: "{n}"': 'Added to the library: "{n}"',
  'فشلت الإضافة: {n}': 'Adding failed: {n}',
  'الصق رابط الـmp3 أولًا': 'Paste the mp3 link first',
  'صوت من الإنترنت': 'Sound from the internet',
  'تعذّر فتح المتصفح: {n}': 'Could not open the browser: {n}',
  'تحميل أصوات': 'Sound Downloads',
  'ابحث عن صوت…': 'Search for a sound…',
  'بحث': 'Search',
  'اللوحات': 'Boards',
  'فارغ.': 'Empty.',
  '{n} ث': '{n}s',
  'المزيد': 'More',
  'اذهب لصفحة… (مثال 400)': 'Go to page… (e.g. 400)',
  'اذهب': 'Go',
  'صوت من خارج القائمة؟': 'A sound outside the list?',
  'افتح الموقع في المتصفح، انسخ رابط ملف الـmp3 مباشرة، والصقه هنا.':
      'Open the site in your browser, copy the direct mp3 file link, and paste it here.',
  'افتح myinstants في المتصفح': 'Open myinstants in the browser',
  'رابط الـmp3': 'mp3 link',
  'تحميل وإضافة للمكتبة': 'Download and add to library',
  // host_engine
  '✖️ {n} مضاعفة نشطة لهذا الدور':
      '✖️ {n} — doubling is active this round',
  '⚡ {a} أعاد دور {b}': '⚡ {a} made {b} redo the take',
  '🛡️ {n} درع نشط — أخفض جولة تُحذف':
      "🛡️ {n}'s shield is active — their worst round is dropped",
  '✖️ مضاعفة نشطة لهذا الدور':
      '✖️ Doubling is active this round',
  'لاعب': 'Player',
  'المباراة جارية': 'A match is already running',
  'لازم هاتفين على الأقل — للعب لوحدك استخدم اللعب بموبايل واحد':
      'You need at least two phones — for solo play use Play on one phone',
  'اختر صوتًا واحدًا على الأقل': 'Pick at least one sound',
  'نجمع أصوات اللاعبين…': "Gathering players' sounds…",
  'لا توجد أصوات — ليضف كل لاعب صوتًا من 2–6 ثوانٍ':
      'No sounds — each player must add a 2–6 second sound',
  'المركز {n} · ×2': 'Place {n} · ×2',
  'المركز {n}': 'Place {n}',
  // gameplay_screen (solo turn script + LAN stage)
  'نجهّز الحفلة…': 'Getting the party ready…',
  'لا توجد أصوات بعد — أضف صوتًا من المكتبة.':
      'No sounds yet — add one from the library.',
  'تعذّر بدء الحفلة. حاول مرة أخرى.':
      'Could not start the party. Try again.',
  'لا يوجد صوت لهذا الدور': 'No sound for this round',
  'انتهى الوقت — 0': "Time's up — 0",
  'استمع… يُشغَّل مرة واحدة': 'Listen… playing once',
  'قلّد الآن!': 'Mimic now!',
  'لم نسمع شيئًا — 0': "We didn't hear anything — 0",
  'تعذّر إكمال الدور — النتيجة 0': 'Could not finish the turn — score 0',
  'جهّز صوتك': 'Get your sound ready', 'اقترب': 'Closer', 'هيّا!': 'Go!',
  'هل تريد المغادرة؟': 'Leave the match?',
  'مغادرة المضيف تنهي الحفلة للجميع.':
      'Leaving as host ends the party for everyone.',
  'ستغادر الغرفة وستكمل اللعبة بدونك.':
      'You will leave the room and the game goes on without you.',
  'البقاء': 'Stay', 'مغادرة': 'Leave',
  'الجولة {a} من {b}': 'Round {a} of {b}',
  'نجهّز…': 'Getting ready…',
  'برق — يعيد دور اللاعب الحالي مرة واحدة':
      'Bolt — makes the current player redo the take once',
  'درع — يحذف أسوأ جولة من المجموع النهائي':
      'Shield — drops one worst round from the final total',
  'لا توجد مباراة نشطة.': 'No active match.',
  'اختر التحدي': 'Pick the challenge',
  'استمع قبل التثبيت. لن يسمع الباقون معاينتك.':
      'Preview before you confirm. The others will not hear your preview.',
  'اختر صوتًا': 'Pick a sound',
  'هذا هو التحدي': 'This is the challenge',
  '…يختار الصوت': '…is picking the sound',
  '{n} يختار الصوت…': '{n} is picking the sound…',
  'استعد، فدورك قادم بعده.': 'Get set — your turn comes right after.',
  'حان دور {n}': "It's {n}'s turn",
  'ابقَ صامتًا — لا سماعة ولا ميكروفون لديك الآن.':
      'Stay silent — you have no mic or earphones this turn.',
  'النتيجة القادمة من المضيف…': 'The score is coming from the host…',
  'نتيجتك {s}': 'Your score: {s}',
  'السبب: {n}': 'Reason: {n}',
  'انتهت الحفلة': 'Party over',
  'نجهّز الأصوات…': 'Preparing the sounds…',
  'حان دورك يا {n}': "It's your turn, {n}",
  'اضغط الزر: ستستمع إلى الصوت مرة واحدة، ثم تنتظر ٣ ثوانٍ، وبعدها يُسجَّل تقليدك تلقائيًا.':
      'Tap the button: you hear the sound once, wait 3 seconds, then your mimic is recorded automatically.',
  'ابدأ الاستماع': 'Start Listening',
  'استعد…': 'Get set…',
  'قلّد الآن': 'Mimic now',
  'استمع… مرة واحدة': 'Listen… once',
  'دورك… جهّز نفسك': 'Your turn… get ready',
  'يلزم إذن الميكروفون لسماع تقليدك.':
      'Microphone permission is needed to hear your mimic.',
  'اسمح للميكروفون': 'Allow the microphone',
  'أضف صوتًا من المكتبة': 'Add a sound from the library',
  'يا {n}، اختر التحدي': '{n}, pick the challenge',
  'ليبتعد الباقون الآن. سيقلدون قبلك، وستلعب أخيرًا.':
      'The others step away now. They mimic before you, and you play last.',
  'اختر الصوت، وبعدها تسمعه مرة واحدة وتقلّده.':
      'Pick the sound; then you hear it once and mimic it.',
  'اختر أصوات الجولات': 'Pick the round sounds',
  'اضغط بالترتيب. سيقلد الجميع كل صوت قبل الانتقال إلى التالي.':
      'Tap in order. Everyone mimics each sound before moving to the next.',
  'ابدأ ({n})': 'Start ({n})',
  'قبل البداية': 'Before we start',
  'مرّر الهاتف إلى': 'Hand the phone to',
  'التحدي: {n}': 'Challenge: {n}',
  'أنا {n} — ابدأ': "I'm {n} — start",
  'نحسب درجة التقليد…': 'Scoring the mimic…',
  'مرّر الهاتف للاعب التالي': 'Hand the phone to the next player',
  'اختيار الصوت التالي': 'Next sound pick',
  'الصوت التالي': 'Next sound',
  'النتائج': 'Results',
  '✖️ ×2 مضاعفة': '✖️ ×2 double',
  'أعلى تقليد لهذا الصوت حتى الآن': 'Top mimic on this sound so far',
  'إنهاء الحفلة': 'End the party',
  'انتهت الجولة': 'Round over',
  'نتيجة “{n}”': 'Score for “{n}”',
  'الجولة التالية': 'Next round',
  'النتائج النهائية': 'Final results',
  'مضاعفة — نقاط هذا الدور ×2، تُجهّز قبل بدء الاستماع':
      "Double — this round's points ×2. Arm it before you start listening.",
  'مسلّحة لهذا الدور': 'Armed this round',
  '(المخزون {n})': '({n} left)',
  'اضغط الزر: تسمع الصوت مرة، تنتظر ٣ ثوانٍ، وبعدين يتسجل تقليدك تلقائيًا.':
      'Tap the button: you hear the sound once, wait 3 seconds, then your mimic is recorded automatically.',
  'مجموع {n}: {s}': '{n} total: {s}',
  'لم نسمعك جيدًا — قرّب الهاتف وقلّد بصوت أوضح':
      "We didn't hear you well — hold the phone closer and mimic louder",
  '“{n}”': '“{n}”',
  'من سيلعب؟': "Who's playing?",
  'تناوبوا على الهاتف؛ يمسكه كل لاعب عند دوره. '
      'تستمع إلى الصوت مرة واحدة، ثم تنتظر ٣ ثوانٍ، وتقلّد، وتحصل على نقاطك.':
      'Take turns on one phone — each player holds it on their turn. You '
          'hear the sound once, wait 3 seconds, then mimic it and score.',
  'أصواتك الجاهزة: {n}': 'Sounds ready: {n}',
  'اسم اللاعب': 'Player name',
  'لاعب {n}': 'Player {n}',
  'لاعب 1': 'Player 1',
  'تعديل الاسم': 'Edit name',
  'أنت': 'You',
  'مشارك': 'Player',
  'أضف لاعب': 'Add player',
  'أضف أصوات من المكتبة': 'Add sounds from the library',
  'أضف صوتًا من ٢–٦ ثوانٍ أولًا': 'Add a 2–6 second sound first',
  'يلزم إذن الميكروفون لتقييم التقليد': 'Mic permission is needed to score your mimic',
  'الحد الأقصى ٥ لاعبين على الهاتف نفسه': 'Up to 5 players on one phone',
  'لنبدأ': "Let's start",
  'إلغاء': 'Cancel',
  'حفظ': 'Save',
};

String t(String key, [Map<String, Object?>? params]) {
  var s = currentLanguage == AppLanguage.arabic ? key : (_en[key] ?? key);
  if (params != null) {
    for (final entry in params.entries) {
      s = s.replaceAll('{${entry.key}}', '${entry.value}');
    }
  }
  return s;
}
