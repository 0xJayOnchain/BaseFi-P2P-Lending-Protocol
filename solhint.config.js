module.exports = {
  extends: ["solhint:recommended"],
  rules: {
    // Relax NatSpec to reduce noise overall
    "use-natspec": [
      "warn",
      {
        functions: ["public", "external"],
        contract: true,
        methods: false,
        events: false
      }
    ],
    // Common style relaxations
    "func-name-mixedcase": "off",
    "var-name-mixedcase": "off",
    // Don't enforce one-contract-per-file in tests/mocks
    "one-contract-per-file": "error",
  },
  overrides: [
    {
      files: ["test/**/*.sol", "src/mocks/**/*.sol"],
      rules: {
        // Tests and mocks can have multiple contracts and minimal NatSpec
        "one-contract-per-file": "off",
        "use-natspec": "off",
        "state-visibility": "warn"
      }
    },
    {
      files: ["src/interfaces/**/*.sol"],
      rules: {
        // Interfaces typically keep docs light
        "use-natspec": [
          "warn",
          {
            functions: ["public", "external"],
            contract: false,
            methods: false,
            events: false
          }
        ]
      }
    }
  ]
};
