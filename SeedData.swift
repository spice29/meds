import Foundation

/// الأدوية الأولية: تنضاف تلقائياً أول مرة يشتغل فيها التطبيق فقط.
/// لو تبي تضيف أدوية بعد، أضف أسطر جديدة هنا، أو أضفها من التطبيق نفسه.
extension Store {
    static let seed: [Medication] = [
        // ---- 8 صباحاً ----
        Medication(name: "تاينول (Tylenol) 500 ملجم", qty: 1, slots: [.morning, .afternoon, .evening]),
        Medication(name: "كالسيوم سيترات 950 ملجم", note: "مع الفطور", qty: 2, slots: [.morning]),
        Medication(name: "ديكساميثازون 1 ملجم", note: "المجموع 4 ملجم", qty: 4, slots: [.morning]),
        Medication(name: "إليكويس 2.5 ملجم", qty: 1, slots: [.morning, .evening]),
        Medication(name: "بيبسيد 20 ملجم", qty: 1, slots: [.morning, .evening]),
        Medication(name: "ميثادون 10 ملجم", note: "المجموع 20 ملجم", qty: 2, slots: [.morning, .evening]),
        Medication(name: "روباكسين (Robaxin) 750 ملجم", qty: 1, slots: [.morning, .afternoon, .evening]),
        Medication(name: "ليريكا (Lyrica) 150 ملجم", note: "كبسولة", qty: 1, slots: [.morning, .afternoon, .evening]),

        // ---- 2 ظهراً ---- الأدوية الثلاثة (تاينول، روباكسين، ليريكا) مضافة فوق بالوقتين: .morning و .afternoon
        // ---- 8 مساءً ---- ميثادون، إليكويس، بيبسيد، تاينول، روباكسين، ليريكا: مضافة فوق بوقت .evening
    ]
}
