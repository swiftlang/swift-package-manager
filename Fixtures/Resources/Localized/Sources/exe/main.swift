import Foundation

func localizationBundle(forLanguage language: String) -> Bundle? {
	if let path = Bundle.module.path(forResource: language, ofType: "lproj") {
		return Bundle(path: path)
	} else {
		return nil
	}
}

// Spanish localization (based on defaultLocalization).
print(NSLocalizedString("hello_world", bundle: .module, comment: ""))

// German localization.
if let germanBundle = localizationBundle(forLanguage: "de") {
	print(NSLocalizedString("hello_world", bundle: germanBundle, comment: ""))
}

// French localization.
if let frenchBundle = localizationBundle(forLanguage: "fr") {
	print(NSLocalizedString("hello_world", bundle: frenchBundle, comment: ""))
}
