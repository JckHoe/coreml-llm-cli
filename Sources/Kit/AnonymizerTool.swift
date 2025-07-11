import Foundation

/// Tool for anonymizing text by replacing names with placeholders
public class AnonymizerTool: Tool {
    
    public let name = "anonymize_text"
    public let description = "Anonymizes text by detecting and replacing names with placeholders"
    
    public let parameters: [ToolParameter] = [
        ToolParameter(
            name: "text",
            description: "The text to anonymize",
            type: .string,
            required: true
        )
    ]
    
    // Common first names for detection
    private let commonFirstNames = [
        "james", "mary", "john", "patricia", "robert", "jennifer", "michael", "linda",
        "david", "elizabeth", "william", "barbara", "richard", "susan", "joseph", "jessica",
        "thomas", "sarah", "chris", "karen", "christopher", "nancy", "daniel", "lisa",
        "matthew", "betty", "anthony", "helen", "mark", "sandra", "donald", "donna",
        "steven", "carol", "paul", "ruth", "andrew", "sharon", "joshua", "michelle",
        "kenneth", "laura", "kevin", "sarah", "brian", "kimberly", "george", "deborah",
        "edward", "dorothy", "ronald", "lisa", "timothy", "nancy", "jason", "karen",
        "jeffrey", "betty", "ryan", "helen", "jacob", "sandra", "gary", "donna",
        "nicholas", "carol", "eric", "ruth", "jonathan", "sharon", "stephen", "michelle",
        "larry", "laura", "justin", "emily", "scott", "kimberly", "brandon", "deborah",
        "benjamin", "dorothy", "samuel", "amy", "gregory", "angela", "alexander", "ashley",
        "patrick", "brenda", "frank", "emma", "raymond", "olivia", "jack", "cynthia",
        "dennis", "marie", "jerry", "janet", "tyler", "catherine", "aaron", "frances",
        "jose", "christine", "henry", "samantha", "adam", "debra", "douglas", "rachel",
        "nathan", "carolyn", "peter", "janet", "zachary", "virginia", "kyle", "maria"
    ]
    
    // Common last names for detection
    private let commonLastNames = [
        "smith", "johnson", "williams", "brown", "jones", "garcia", "miller", "davis",
        "rodriguez", "martinez", "hernandez", "lopez", "gonzalez", "wilson", "anderson", "thomas",
        "taylor", "moore", "jackson", "martin", "lee", "perez", "thompson", "white",
        "harris", "sanchez", "clark", "ramirez", "lewis", "robinson", "walker", "young",
        "allen", "king", "wright", "scott", "torres", "nguyen", "hill", "flores",
        "green", "adams", "nelson", "baker", "hall", "rivera", "campbell", "mitchell",
        "carter", "roberts", "gomez", "phillips", "evans", "turner", "diaz", "parker",
        "cruz", "edwards", "collins", "reyes", "stewart", "morris", "morales", "murphy",
        "cook", "rogers", "gutierrez", "ortiz", "morgan", "cooper", "peterson", "bailey",
        "reed", "kelly", "howard", "ramos", "kim", "cox", "ward", "richardson",
        "watson", "brooks", "chavez", "wood", "james", "bennett", "gray", "mendoza",
        "ruiz", "hughes", "price", "alvarez", "castillo", "sanders", "patel", "myers"
    ]
    
    // Placeholder names for replacement
    private let placeholderFirstNames = [
        "Alex", "Jordan", "Taylor", "Casey", "Riley", "Quinn", "Morgan", "Drew",
        "Avery", "Sage", "River", "Phoenix", "Skylar", "Rowan", "Emery", "Finley",
        "Hayden", "Remy", "Indigo", "Kai", "Lane", "Marley", "Nova", "Onyx",
        "Peyton", "Reese", "Sage", "Tatum", "Vale", "Wren", "Zion", "Bay"
    ]
    
    private let placeholderLastNames = [
        "Anderson", "Bennett", "Carter", "Davis", "Ellis", "Foster", "Gray", "Hall",
        "Irving", "Jackson", "Kelly", "Lane", "Miller", "Norton", "Oliver", "Parker",
        "Quinn", "Reed", "Stone", "Taylor", "Union", "Vale", "White", "Young",
        "Zeller", "Baker", "Clark", "Dean", "Evans", "Ford", "Green", "Hill"
    ]
    
    public init() {}
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let text = parameters["text"] as? String else {
            return ToolResult.failure("Missing required parameter: text")
        }
        
        if text.isEmpty {
            return ToolResult.success([])
        }
        
        let replacements = detectAndReplaceNames(in: text)
        
        // Create response in the format requested: array of maps with original_text, replacement_text, category
        let responseData = replacements.map { replacement in
            return [
                "original_text": replacement.original,
                "replacement_text": replacement.replacement,
                "category": replacement.category
            ]
        }
        
        return ToolResult.success(responseData)
    }
    
    /// Detect and replace names in text
    private func detectAndReplaceNames(in text: String) -> [NameReplacement] {
        var replacements: [NameReplacement] = []
        var processedText = text
        var usedPlaceholders: Set<String> = []
        
        // Pattern to match potential names (capitalized words)
        let namePattern = #"\b[A-Z][a-zA-Z]{1,}\b"#
        let regex = try? NSRegularExpression(pattern: namePattern, options: [])
        
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.count)) ?? []
        
        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            let range = match.range
            if let stringRange = Range(range, in: text) {
                let word = String(text[stringRange]).lowercased()
                let originalWord = String(text[stringRange])
                
                // Check if it's a common first name
                if commonFirstNames.contains(word) {
                    let placeholder = generateUniquePlaceholder(type: .firstName, used: &usedPlaceholders)
                    replacements.append(NameReplacement(
                        original: originalWord,
                        replacement: placeholder,
                        category: "first_name"
                    ))
                }
                // Check if it's a common last name
                else if commonLastNames.contains(word) {
                    let placeholder = generateUniquePlaceholder(type: .lastName, used: &usedPlaceholders)
                    replacements.append(NameReplacement(
                        original: originalWord,
                        replacement: placeholder,
                        category: "last_name"
                    ))
                }
                // Check for potential names (capitalized words not at sentence start)
                else if isLikelyName(word: originalWord, in: text, at: range) {
                    let placeholder = generateUniquePlaceholder(type: .firstName, used: &usedPlaceholders)
                    replacements.append(NameReplacement(
                        original: originalWord,
                        replacement: placeholder,
                        category: "potential_name"
                    ))
                }
            }
        }
        
        // Also check for full names (FirstName LastName patterns)
        let fullNamePattern = #"\b[A-Z][a-zA-Z]{1,}\s+[A-Z][a-zA-Z]{1,}\b"#
        let fullNameRegex = try? NSRegularExpression(pattern: fullNamePattern, options: [])
        let fullNameMatches = fullNameRegex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.count)) ?? []
        
        for match in fullNameMatches.reversed() {
            let range = match.range
            if let stringRange = Range(range, in: text) {
                let fullName = String(text[stringRange])
                let components = fullName.components(separatedBy: " ")
                
                if components.count == 2 {
                    let firstName = components[0].lowercased()
                    let lastName = components[1].lowercased()
                    
                    // Check if both parts are likely names
                    if commonFirstNames.contains(firstName) || commonLastNames.contains(lastName) {
                        let firstPlaceholder = generateUniquePlaceholder(type: .firstName, used: &usedPlaceholders)
                        let lastPlaceholder = generateUniquePlaceholder(type: .lastName, used: &usedPlaceholders)
                        
                        replacements.append(NameReplacement(
                            original: fullName,
                            replacement: "\(firstPlaceholder) \(lastPlaceholder)",
                            category: "full_name"
                        ))
                    }
                }
            }
        }
        
        return replacements
    }
    
    /// Check if a word is likely a name based on context
    private func isLikelyName(word: String, in text: String, at range: NSRange) -> Bool {
        // Skip if it's at the beginning of a sentence
        if range.location == 0 {
            return false
        }
        
        // Check if preceded by common name indicators
        let precedingText = String(text.prefix(range.location))
        let nameIndicators = ["mr.", "mrs.", "ms.", "dr.", "prof.", "hello", "hi", "dear", "from", "by", "to"]
        
        for indicator in nameIndicators {
            if precedingText.lowercased().hasSuffix(indicator) {
                return true
            }
        }
        
        // Check if it's a reasonably long word (likely not an abbreviation)
        return word.count >= 3 && word.count <= 15
    }
    
    /// Generate a unique placeholder name
    private func generateUniquePlaceholder(type: PlaceholderType, used: inout Set<String>) -> String {
        let candidates = type == .firstName ? placeholderFirstNames : placeholderLastNames
        
        for candidate in candidates {
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
        }
        
        // If all candidates are used, generate a numbered variant
        let baseName = candidates.randomElement() ?? "Person"
        var counter = 1
        while used.contains("\(baseName)\(counter)") {
            counter += 1
        }
        
        let placeholder = "\(baseName)\(counter)"
        used.insert(placeholder)
        return placeholder
    }
    
    private enum PlaceholderType {
        case firstName
        case lastName
    }
}

/// Represents a name replacement
private struct NameReplacement {
    let original: String
    let replacement: String
    let category: String
}