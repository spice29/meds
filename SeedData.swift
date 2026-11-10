import Foundation

/// الأدوية الأولية: تنضاف تلقائياً أول مرة يشتغل فيها التطبيق فقط.
/// بعدها كل تعديل تسويه من داخل التطبيق ينحفظ ولا يتأثر بهذا الملف.
extension Store {
    private static let am = DoseTime(hour: 8, minute: 0)
    private static let pm = DoseTime(hour: 14, minute: 0)
    private static let eve = DoseTime(hour: 20, minute: 0)

    static let seed: [Medication] = [
        Medication(name: "تاينول (Tylenol) 500 ملجم", form: .tablet, dose: 1,
                   times: [am, pm, eve]),
        Medication(name: "كالسيوم سيترات 950 ملجم", form: .tablet, dose: 2,
                   meal: .withMeal, times: [am], note: "مع الفطور"),
        Medication(name: "ديكساميثازون 1 ملجم", form: .tablet, dose: 4,
                   times: [am], note: "المجموع 4 ملجم"),
        Medication(name: "إليكويس 2.5 ملجم", form: .tablet, dose: 1,
                   times: [am, eve]),
        Medication(name: "بيبسيد 20 ملجم", form: .tablet, dose: 1,
                   times: [am, eve]),
        Medication(name: "ميثادون 10 ملجم", form: .tablet, dose: 2,
                   times: [am, eve], note: "المجموع 20 ملجم"),
        Medication(name: "روباكسين (Robaxin) 750 ملجم", form: .tablet, dose: 1,
                   times: [am, pm, eve]),
        Medication(name: "ليريكا (Lyrica) 150 ملجم", form: .capsule, dose: 1,
                   times: [am, pm, eve]),
    ]
}
