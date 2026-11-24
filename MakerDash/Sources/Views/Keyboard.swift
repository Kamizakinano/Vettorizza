import SwiftUI
import UIKit

extension View {
    /// Pulsante "Fine" sopra la tastiera + chiusura trascinando la lista.
    func keyboardDone() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }.bold()
                }
            }
    }
}
