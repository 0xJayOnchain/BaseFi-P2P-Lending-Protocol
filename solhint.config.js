module.exports = {
  extends: ["solhint:recommended"],
  rules: {
    // Keep NatSpec focused on user-facing APIs; no need to tag every variable or internal function
    "use-natspec": [
      "warn",
      {
        contract: true,
        functions: ["public", "external"],
        events: false,
        methods: false,
        // do not require variable-level @notice anywhere
        variables: false,
      }
    ],
    // Common style relaxations
    "func-name-mixedcase": "off",
    "var-name-mixedcase": "off",
    // Enforce one-contract-per-file by default (tests override below)
    "one-contract-per-file": "error",
  },
  overrides: [
    {
      files: ["test/**/*.sol", "src/mocks/**/*.sol"],
      rules: {
        // Tests and mocks: no NatSpec, allow multiple contracts, keep visibility as a gentle reminder
        "use-natspec": "off",
        "one-contract-per-file": "off",
        "state-visibility": "warn",
      }
    },
    {
      files: ["src/interfaces/**/*.sol"],
      rules: {
        // Interfaces should be light; doc only public/external functions if you want
        "use-natspec": [
          "warn",
          {
            contract: false,
            functions: ["public", "external"],
            events: false,
            methods: false,
            variables: false,
          }
        ]
      }
    }
  ]
};
