export type EntityType = "person" | "organization";

export type EntityRef = {
  id: string;
  type: EntityType;
  label: string;
  extra?: string;
};

export type EntitySuggestion = EntityRef;

export type YearRange = { from: number; to: number };

export type PromptTemplate = {
  id: string;
  title: string;
  icon?: string;
  entityTypes: EntityType[];
  intent?: string;
  description?: string;
};
