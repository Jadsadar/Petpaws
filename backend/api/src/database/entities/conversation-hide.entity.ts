import { Column, Entity, PrimaryColumn } from 'typeorm';

@Entity({ name: 'conversation_hides' })
export class ConversationHide {
  @PrimaryColumn({ name: 'conversation_id', type: 'uuid' })
  conversationId!: string;

  @PrimaryColumn({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'hidden_at', type: 'timestamptz' })
  hiddenAt!: Date;
}
