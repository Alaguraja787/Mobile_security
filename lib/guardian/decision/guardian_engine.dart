import 'dart:math';

import '../../models/app_telemetry.dart';
import '../../models/privacy_event.dart';
import '../context/context_analyzer.dart';
import '../evidence/evidence_interpreter.dart';
import '../explanation/explanation_generator.dart';
import '../interfaces/phase2_intelligence_provider.dart';
import '../interfaces/phase4_action_handler.dart';
import '../mocks/mock_phase2_provider.dart';
import '../models/guardian_decision.dart';
import '../models/guardian_input.dart';
import '../models/severity_confidence.dart';
import '../reasoning/guardian_reasoner.dart';
import '../reasoning/llm_reasoner.dart';
import '../recommendations/recommendation_engine.dart';
import '../risk/risk_assessment_engine.dart';

/// Main Orchestrator for Phase 3 — Guardian Intelligence.
class GuardianEngine {
  final Phase2IntelligenceProvider phase2Provider;
  final EvidenceInterpreter evidenceInterpreter;
  final ContextAnalyzer contextAnalyzer;
  final GuardianReasoner reasoner;
  final RiskAssessmentEngine riskEngine;
  final ExplanationGenerator explanationGenerator;
  final RecommendationEngine recommendationEngine;

  GuardianEngine({
    Phase2IntelligenceProvider? phase2Provider,
    EvidenceInterpreter? evidenceInterpreter,
    ContextAnalyzer? contextAnalyzer,
    GuardianReasoner? reasoner,
    RiskAssessmentEngine? riskEngine,
    ExplanationGenerator? explanationGenerator,
    RecommendationEngine? recommendationEngine,
  })  : phase2Provider = phase2Provider ?? MockPhase2Provider(),
        evidenceInterpreter = evidenceInterpreter ?? EvidenceInterpreter(),
        contextAnalyzer = contextAnalyzer ?? ContextAnalyzer(),
        reasoner = reasoner ?? LLMReasoner(),
        riskEngine = riskEngine ?? RiskAssessmentEngine(),
        explanationGenerator = explanationGenerator ?? ExplanationGenerator(),
        recommendationEngine = recommendationEngine ?? RecommendationEngine();

  /// Executes the Guardian agentic cycle: OBSERVE -> INTERPRET -> CONTEXT -> ASSESS -> DECIDE -> RECOMMEND.
  Future<GuardianDecision> evaluate({
    AppTelemetry? app,
    required PrivacyEvent event,
    String? recordId,
    String? sessionId,
    Map<String, dynamic>? historyContext,
  }) async {
    final String decisionId = 'dec_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';

    // 1. Fetch Phase 2 Intelligence Snapshot (or mock boundary)
    final intelSnapshot = await phase2Provider.getIntelligence(app: app, event: event);

    // 2. Build GuardianInput
    final input = GuardianInput(
      recordId: recordId,
      sessionId: sessionId,
      targetApp: app,
      event: event,
      intelligenceSnapshot: intelSnapshot,
      historyContext: historyContext,
    );

    // 3. Interpret Telemetry Evidence & Availability States
    final interpretation = evidenceInterpreter.interpret(input);

    // 4. Analyze Context & Derive Inferences
    final contextInferences = contextAnalyzer.analyzeContext(input, interpretation);

    // 5. Perform Evidence-First Reasoning
    final reasoningOutput = await reasoner.reason(
      input: input,
      interpretation: interpretation,
      contextInferences: contextInferences,
    );

    // 6. Assess Severity & Confidence Separately
    final assessment = riskEngine.assess(input, interpretation, reasoningOutput.inferences);

    // 7. Generate Explanations & Recommendations
    final userExplanation = explanationGenerator.generateExplanation(
      input: input,
      interpretation: interpretation,
      reasoningOutput: reasoningOutput,
      severity: assessment.severity,
      confidence: assessment.confidence,
    );

    final recommendations = recommendationEngine.generateRecommendations(
      input: input,
      interpretation: interpretation,
      inferences: reasoningOutput.inferences,
      severity: assessment.severity,
    );

    final bool requiresAttention = assessment.severity == GuardianSeverity.HIGH ||
        assessment.severity == GuardianSeverity.CRITICAL;

    // 8. Generate Phase 4 Action Request if attention is required
    Phase4ActionRequest? actionRequest;
    if (requiresAttention && app != null) {
      actionRequest = Phase4ActionRequest(
        requestId: 'req_${DateTime.now().millisecondsSinceEpoch}',
        decisionId: decisionId,
        targetPackageName: app.packageName,
        actionType: 'PROMPT_USER_PERMISSION_REVIEW',
        reasoningSummary: reasoningOutput.reasoningSummary,
        requiresUserApproval: true,
      );
    }

    return GuardianDecision(
      decisionId: decisionId,
      severity: assessment.severity,
      confidence: assessment.confidence,
      summary: reasoningOutput.userFacingExplanation,
      observedEvidence: interpretation.facts,
      inferences: reasoningOutput.inferences,
      uncertainties: interpretation.uncertainties,
      reasoning: reasoningOutput.reasoningSummary,
      userFacingExplanation: userExplanation,
      recommendations: recommendations,
      requiresUserAttention: requiresAttention,
      phase4ActionRequest: actionRequest,
      responseSource: reasoningOutput.responseSource,
      fallbackCause: reasoningOutput.fallbackCause,
      providerUsed: reasoningOutput.providerUsed,
      modelUsed: reasoningOutput.modelUsed,
      fallbackDepth: reasoningOutput.fallbackDepth,
      fallbackReason: reasoningOutput.fallbackReason,
      httpStatus: reasoningOutput.httpStatus,
      latencyMs: reasoningOutput.latencyMs,
    );
  }
}
